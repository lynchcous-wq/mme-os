import {createHash,createHmac,timingSafeEqual} from "node:crypto";
import {NextResponse} from "next/server";
export const dynamic="force-dynamic";
export const revalidate=0;
const headers={"Cache-Control":"no-store, private"};
function validSignature(raw:string,signature:string,secret:string){
 const parts=signature.split(",").map(x=>x.split("=",2));
 const timestamp=parts.find(x=>x[0]==="t")?.[1];
 const candidates=parts.filter(x=>x[0]==="v1").map(x=>x[1]).filter(Boolean);
 if(!timestamp||!/^\d+$/.test(timestamp)||!candidates.length)return false;
 if(Math.abs(Math.floor(Date.now()/1000)-Number(timestamp))>300)return false;
 const expected=createHmac("sha256",secret).update(timestamp+"."+raw).digest();
 return candidates.some(value=>{try{const actual=Buffer.from(value,"hex");return actual.length===expected.length&&timingSafeEqual(actual,expected);}catch{return false;}});
}
export async function POST(request:Request){
 const secret=process.env.STRIPE_WEBHOOK_SECRET;
 const baseUrl=process.env.SUPABASE_URL??process.env.NEXT_PUBLIC_SUPABASE_URL;
 const serviceKey=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!secret||!baseUrl||!serviceKey)return NextResponse.json({error:"Webhook intake is not configured."},{status:503,headers});
 const raw=await request.text();
 if(raw.length>1024*1024)return NextResponse.json({error:"Webhook payload too large."},{status:413,headers});
 const signature=request.headers.get("stripe-signature")||"";
 if(!validSignature(raw,signature,secret))return NextResponse.json({error:"Invalid webhook signature."},{status:400,headers});
 let event:Record<string,unknown>;
 try{event=JSON.parse(raw) as Record<string,unknown>;}catch{return NextResponse.json({error:"Invalid webhook JSON."},{status:400,headers});}
 const account=typeof event.account==="string"?event.account:null;
 const eventId=typeof event.id==="string"?event.id:"";
 const eventType=typeof event.type==="string"?event.type:"";
 if(!eventId||!eventType||!account)return NextResponse.json({error:"Webhook must include a connected account, event ID and type."},{status:400,headers});
 try{
  const query=new URLSearchParams({select:"id,location_id",provider_key:"eq.stripe",status:"eq.active",external_account_reference:"eq."+account,limit:"2"});
  const found=await fetch(baseUrl+"/rest/v1/mme_pos_financial_connectors?"+query.toString(),{headers:{apikey:serviceKey,Authorization:"Bearer "+serviceKey,Accept:"application/json"},cache:"no-store"});
  if(!found.ok)return NextResponse.json({error:"Connector lookup failed."},{status:503,headers});
  const connectors=await found.json() as Array<{id:string;location_id:string}>;
  if(connectors.length!==1)return NextResponse.json({error:"No unique active Stripe connector matches this account."},{status:404,headers});
  const digest=createHash("sha256").update(raw).digest("hex");
  const saved=await fetch(baseUrl+"/rest/v1/rpc/mme_pos_record_financial_webhook_event",{
   method:"POST",headers:{apikey:serviceKey,Authorization:"Bearer "+serviceKey,"Content-Type":"application/json"},
   body:JSON.stringify({p_connector_id:connectors[0].id,p_provider_event_id:eventId,p_event_type:eventType,p_account_reference:account,p_payload_sha256:digest}),cache:"no-store"});
  if(!saved.ok)return NextResponse.json({error:"Verified event could not be recorded."},{status:503,headers});
  const eventRecordId=await saved.json();
  return NextResponse.json({received:true,event_record_id:eventRecordId},{status:202,headers});
 }catch{return NextResponse.json({error:"Webhook intake failed."},{status:503,headers});}
}
