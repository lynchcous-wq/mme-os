import { NextRequest, NextResponse } from "next/server";
import { requireBrowserUser, setSessionCookies, supabaseConfig } from "@/lib/auth/supabase-session";
export const dynamic = "force-dynamic";
type Row = Record<string, unknown>;
const jsonHeaders = { "Cache-Control": "no-store, max-age=0", Vary: "Cookie" };
export async function GET(request: NextRequest) {
 try {
  const session=await requireBrowserUser(request);
  if(!session.user) return NextResponse.json({error:"Sign in to view your customer dashboard."},{status:401,headers:jsonHeaders});
  const {url}=supabaseConfig(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!key) return NextResponse.json({error:"Customer dashboard is not configured."},{status:503,headers:jsonHeaders});
  const headers={apikey:key,Authorization:"Bearer "+key};
  const get=async(path:string)=>{const r=await fetch(url+"/rest/v1/"+path,{headers,cache:"no-store"});if(!r.ok)throw new Error("Customer dashboard projection unavailable.");return await r.json() as Row[];};
  const links=await get("mme_customer_account_links?auth_user_id=eq."+encodeURIComponent(session.user.id)+"&link_status=eq.active&select=person_id&limit=2");
  if(links.length!==1||typeof links[0].person_id!=="string") return NextResponse.json({error:"Your MME customer identity is not active or has not been linked. Submit an identity review request if needed."},{status:403,headers:jsonHeaders});
  const personId=links[0].person_id;
  const identities=await get("mme_person_identities?person_id=eq."+encodeURIComponent(personId)+"&lifecycle_status=eq.active&select=person_id&limit=2");
  if(identities.length!==1) return NextResponse.json({error:"Your MME customer identity is not active."},{status:403,headers:jsonHeaders});
  const [orders,subscriptions]=await Promise.all([
   get("mme_customer_order_portal?person_id=eq."+encodeURIComponent(personId)+"&select=order_id,order_reference,order_status,order_placed_at,currency_code,order_total,fulfillment_type&order=order_placed_at.desc&limit=50"),
   get("mme_customer_subscription_portal?person_id=eq."+encodeURIComponent(personId)+"&select=subscription_id,subscription_name,subscription_status,current_period_ends_at,cancel_at_period_end,updated_at&order=updated_at.desc&limit=50")
  ]);
  const orderIds=orders.map(row=>row.order_id).filter((id):id is string=>typeof id==="string");
  let fulfillment:Row[]=[],warranties:Row[]=[],refunds:Row[]=[];
  if(orderIds.length){
   const ids="in.("+orderIds.map(id=>encodeURIComponent(id)).join(",")+")";
   [fulfillment,warranties,refunds]=await Promise.all([
    get("mme_customer_order_fulfillment_portal?order_id="+ids+"&select=order_id,fulfillment_status,carrier_name,tracking_number,tracking_url,estimated_delivery_at,pickup_ready_at,picked_up_at"),
    get("mme_customer_order_warranty_portal?order_id="+ids+"&select=warranty_id,order_id,item_reference,warranty_name,warranty_status,starts_at,expires_at&order=expires_at.asc&limit=100"),
    get("mme_customer_order_refund_portal?order_id="+ids+"&select=refund_id,order_id,refund_status,refund_amount,currency_code,requested_at&order=requested_at.desc&limit=100")
   ]);
  }
  const response=NextResponse.json({account:{status:"active",email:session.user.email??null,emailVerified:Boolean(session.user.email_confirmed_at)},orders,fulfillment,warranties,refunds,subscriptions,generatedAt:new Date().toISOString()},{headers:jsonHeaders});
  if(session.refreshed)setSessionCookies(response,session.refreshed);
  return response;
 }catch{return NextResponse.json({error:"Your customer dashboard is temporarily unavailable. Please try again."},{status:503,headers:jsonHeaders});}
}
