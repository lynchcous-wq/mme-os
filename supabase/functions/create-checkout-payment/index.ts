import Stripe from "npm:stripe@17.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.49.1";
const headers={"Access-Control-Allow-Origin":"null","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-idempotency-key","Access-Control-Allow-Methods":"POST, OPTIONS"};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...headers,"Content-Type":"application/json"}});
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers});
 if(req.method!=="POST") return reply({error:"method_not_allowed"},405);
 const auth=req.headers.get("authorization"), key=req.headers.get("x-idempotency-key")??"";
 if(!auth?.startsWith("Bearer ")||key.trim().length<8||key.length>128) return reply({error:"authentication_and_idempotency_required"},401);
 const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 const stripeKey=Deno.env.get("STRIPE_SECRET_KEY"),pricingUrl=Deno.env.get("MME_CHECKOUT_PRICING_URL"),pricingSecret=Deno.env.get("MME_CHECKOUT_PRICING_SECRET");
 if(!url||!anon||!service||!stripeKey||!pricingUrl||!pricingSecret) return reply({error:"checkout_not_configured"},503);
 let body:any; try{body=await req.json()}catch{return reply({error:"invalid_json"},400)}
 if(!body||!Array.isArray(body.items)||body.items.length<1||body.items.length>50||!["pickup","shipping"].includes(body.fulfillment_method)||!body.fulfillment_details||typeof body.fulfillment_details!=="object") return reply({error:"invalid_checkout_request"},400);
 const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:userData,error:userError}=await userClient.auth.getUser();
 if(userError||!userData.user) return reply({error:"unauthorized"},401);
 let priced:any;
 try{
  const response=await fetch(pricingUrl,{method:"POST",headers:{"Authorization":"Bearer "+pricingSecret,"Content-Type":"application/json"},body:JSON.stringify({auth_user_id:userData.user.id,items:body.items,fulfillment_method:body.fulfillment_method,fulfillment_details:body.fulfillment_details})});
  if(!response.ok)return reply({error:"trusted_pricing_unavailable"},503);
  priced=await response.json();
 }catch{return reply({error:"trusted_pricing_unavailable"},503)}
 if(!priced||typeof priced.customer_identity_id!=="string"||!Array.isArray(priced.items)||priced.items.length<1||!Number.isSafeInteger(priced.tax_cents)||priced.tax_cents<0||!Number.isSafeInteger(priced.fulfillment_cents)||priced.fulfillment_cents<0||!Number.isSafeInteger(priced.discount_cents)||priced.discount_cents<0||!priced.fulfillment_snapshot||typeof priced.fulfillment_snapshot!=="object") return reply({error:"trusted_pricing_response_invalid"},502);
 if(priced.items.some((x:any)=>!x||typeof x.product_id!=="string"||typeof x.location_id!=="string"||!Number.isInteger(x.quantity)||x.quantity<1||x.quantity>20||(x.serialized_unit_id!==undefined&&(typeof x.serialized_unit_id!=="string"||x.quantity!==1)))) return reply({error:"invalid_priced_items"},502);
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const expires=new Date(Date.now()+15*60*1000).toISOString();
 const {data:orderId,error:orderError}=await admin.rpc("mme_create_mixed_order_and_reserve",{p_idempotency_key:key,p_customer_identity_id:priced.customer_identity_id,p_fulfillment_method:body.fulfillment_method,p_fulfillment_snapshot:priced.fulfillment_snapshot,p_tax_cents:priced.tax_cents,p_fulfillment_cents:priced.fulfillment_cents,p_discount_cents:priced.discount_cents,p_items:priced.items,p_expires_at:expires});
 if(orderError||!orderId)return reply({error:"order_creation_or_reservation_failed"},409);
 const {data:order,error:readError}=await admin.from("mme_orders").select("id,total_cents,currency,status,customer_identity_id").eq("id",orderId).single();
 if(readError||!order||order.status!=="pending_payment"||order.customer_identity_id!==priced.customer_identity_id)return reply({error:"order_not_payable"},409);
 const stripe=new Stripe(stripeKey,{apiVersion:"2024-12-18.acacia"});
 let intent:Stripe.PaymentIntent;
 try{intent=await stripe.paymentIntents.create({amount:order.total_cents,currency:"usd",automatic_payment_methods:{enabled:true},metadata:{mme_order_id:order.id}},{idempotencyKey:"mme-order-"+order.id})}
 catch{return reply({error:"payment_intent_creation_failed",order_id:order.id},502)}
 if(intent.amount!==order.total_cents||intent.currency!=="usd"||!intent.client_secret)return reply({error:"payment_intent_validation_failed",order_id:order.id},502);
 const {error:bindError}=await admin.rpc("mme_bind_order_payment_intent",{p_order_id:order.id,p_provider_object_id:intent.id,p_expected_amount_cents:order.total_cents,p_currency:order.currency,p_customer_identity_id:order.customer_identity_id});
 if(bindError)return reply({error:"payment_binding_failed_reconciliation_required",order_id:order.id},503);
 return reply({order_id:order.id,payment_intent_id:intent.id,client_secret:intent.client_secret,amount_cents:order.total_cents,currency:order.currency,reservation_expires_at:expires});
});
