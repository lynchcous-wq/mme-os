import {createHash,createHmac,timingSafeEqual} from "node:crypto";
import {NextResponse} from "next/server";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export const revalidate=0;
const headers={"Cache-Control":"no-store, private"};
function verify(raw:Buffer,header:string,secret:string){
 const parts=header.split(",").map(x=>x.split("=",2));
 const ts=parts.find(x=>x[0]==="t")?.[1];
 const signatures=parts.filter(x=>x[0]==="v1").map(x=>x[1]).filter(Boolean);
 if(!ts||!/^\d+$/.test(ts)||!signatures.length||Math.abs(Date.now()/1000-Number(ts))>300)return false;
 const expected=createHmac("sha256",secret).update(ts+".").update(raw).digest();
 return signatures.some(value=>{try{const actual=Buffer.from(value,"hex");return actual.length===expected.length&&timingSafeEqual(actual,expected);}catch{return false;}});
}
export async function POST(request:Request){
 const secret=process.env.STRIPE_WEBHOOK_SECRET;
 const base=process.env.SUPABASE_URL??process.env.NEXT_PUBLIC_SUPABASE_URL;
 const service=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!secret||!base||!service)return NextResponse.json({error:"Stripe webhook is not configured."},{status:503,headers});
 const declared=Number(request.headers.get("content-length")??"0");
 if(Number.isFinite(declared)&&declared>256*1024)return NextResponse.json({error:"Payload too large."},{status:413,headers});
 const raw=Buffer.from(await request.arrayBuffer());
 if(raw.length>256*1024)return NextResponse.json({error:"Payload too large."},{status:413,headers});
 if(!verify(raw,request.headers.get("stripe-signature")??"",secret))return NextResponse.json({error:"Invalid Stripe signature."},{status:400,headers});
 let event:Record<string,unknown>;
 try{event=JSON.parse(raw.toString("utf8")) as Record<string,unknown>;}catch{return NextResponse.json({error:"Invalid JSON."},{status:400,headers});}
 const eventId=typeof event.id==="string"?event.id:"";
 const eventType=typeof event.type==="string"?event.type:"";
 const account=typeof event.account==="string"?event.account:"";
 const data=event.data&&typeof event.data==="object"?event.data as Record<string,unknown>:{};
 const refund=data.object&&typeof data.object==="object"?data.object as Record<string,unknown>:{};
 const metadata=refund.metadata&&typeof refund.metadata==="object"?refund.metadata as Record<string,unknown>:{};
 const requestId=typeof metadata.mme_refund_request_id==="string"?metadata.mme_refund_request_id:"";
 const refundId=typeof refund.id==="string"?refund.id:"";
 const paymentIntent=typeof refund.payment_intent==="string"?refund.payment_intent:
  refund.payment_intent&&typeof refund.payment_intent==="object"&&typeof (refund.payment_intent as Record<string,unknown>).id==="string"?
   String((refund.payment_intent as Record<string,unknown>).id):"";
 const amount=typeof refund.amount==="number"&&Number.isSafeInteger(refund.amount)?refund.amount:0;
 const currency=typeof refund.currency==="string"?refund.currency.toUpperCase():"";
 const providerStatus=refund.status==="succeeded"?"succeeded":refund.status==="failed"||refund.status==="canceled"?"failed":"pending";
 if(!eventId||!["refund.created","refund.updated"].includes(eventType)||!account||!requestId||!refundId||!paymentIntent||amount<=0||!/^[A-Z]{3}$/.test(currency))
  return NextResponse.json({error:"Unsupported or incomplete refund event."},{status:400,headers});
 try{
  const response=await fetch(base+"/rest/v1/rpc/mme_pos_reconcile_stripe_refund_webhook",{
   method:"POST",headers:{apikey:service,Authorization:"Bearer "+service,"Content-Type":"application/json"},
   body:JSON.stringify({p_provider_event_id:eventId,p_event_type:eventType,
    p_payload_sha256:createHash("sha256").update(raw).digest("hex"),
    p_refund_request_id:requestId,p_provider_account_reference:account,
    p_provider_refund_reference:refundId,p_provider_payment_reference:paymentIntent,
    p_amount_minor:amount,p_currency:currency,p_provider_status:providerStatus}),cache:"no-store"
  });
  if(!response.ok)return NextResponse.json({error:"Verified refund event could not be reconciled."},{status:503,headers});
  const result=await response.json();
  return NextResponse.json({received:true,result},{status:202,headers});
 }catch{return NextResponse.json({error:"Stripe webhook processing failed."},{status:503,headers});}
}
