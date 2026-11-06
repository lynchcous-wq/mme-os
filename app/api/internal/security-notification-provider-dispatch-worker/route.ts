import { NextRequest, NextResponse } from "next/server";
import { randomUUID, timingSafeEqual } from "node:crypto";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
function authorized(req: NextRequest) {
 const expected = process.env.MME_NOTIFICATION_WORKER_SECRET ?? "";
 const supplied = (req.headers.get("authorization") ?? "").match(/^Bearer\\s+(.+)$/i)?.[1] ?? "";
 if (!expected || !supplied) return false;
 const a = Buffer.from(expected), b = Buffer.from(supplied);
 return a.length === b.length && timingSafeEqual(a,b);
}
async function db(url:string,key:string,path:string,method="POST",body?:unknown) {
 return fetch(url+"/rest/v1/"+path,{method,headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json",Prefer:"return=representation"},...(body===undefined?{}:{body:JSON.stringify(body)}),cache:"no-store"});
}
export async function POST(req:NextRequest) {
 const requestId=randomUUID();
 if(!authorized(req)) return NextResponse.json({error:"worker_authentication_failed",requestId},{status:401});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key) return NextResponse.json({error:"worker_configuration_missing",requestId},{status:503});
 const endpoint=process.env.MME_NOTIFICATION_PROVIDER_WEBHOOK_URL,secret=process.env.MME_NOTIFICATION_PROVIDER_WEBHOOK_SECRET;
 if(!endpoint||!secret) return NextResponse.json({error:"provider_adapter_not_configured",requestId},{status:503});
 let target:URL; try { target=new URL(endpoint); } catch { return NextResponse.json({error:"invalid_provider_url",requestId},{status:503}); }
 if(target.protocol!=="https:") return NextResponse.json({error:"https_required",requestId},{status:503});
 const input=await req.json().catch(()=>({})),limit=Math.max(1,Math.min(100,Number(input?.limit)||25));
 const claimed=await db(url,key,"rpc/mme_security_notification_claim_due","POST",{p_limit:limit});
 if(!claimed.ok) return NextResponse.json({error:"claim_failed",requestId},{status:502});
 const rows=await claimed.json(),results=[];
 for(const n of rows) {
  if(n.channel==="in_app") { results.push({id:n.notification_id,status:"in_app_requires_existing_feed"}); continue; }
  try {
   const response=await fetch(target.toString(),{method:"POST",headers:{"Content-Type":"application/json","X-Provider-Key":secret,"Idempotency-Key":n.idempotency_key??n.notification_id},body:JSON.stringify({notificationId:n.notification_id,incidentId:n.incident_id,recipientRole:n.recipient_role,recipientUserId:n.recipient_user_id,type:n.notification_type,channel:n.channel,payload:n.payload,attempt:n.delivery_attempts}),signal:AbortSignal.timeout(12000),cache:"no-store"});
   const result=await response.json().catch(()=>({}));
   results.push({id:n.notification_id,status:response.ok?result.status??"accepted":"provider_failed"});
  } catch { results.push({id:n.notification_id,status:"provider_unreachable"}); }
 }
 return NextResponse.json({requestId,claimed:rows.length,results},{headers:{"Cache-Control":"no-store"}});
}