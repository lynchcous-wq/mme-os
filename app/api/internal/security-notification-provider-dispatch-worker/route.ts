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
   const status=response.ok&&["accepted","delivered"].includes(result?.status)?result.status:"failed";
   const errorMessage=status==="failed"?(typeof result?.error==="string"?result.error:"provider_http_"+response.status):null;
   const attempt={notification_id:n.notification_id,attempt_number:n.delivery_attempts,channel:n.channel,provider:typeof result?.provider==="string"?result.provider.slice(0,80):"mme-webhook-adapter",status,provider_reference:typeof result?.providerReference==="string"?result.providerReference.slice(0,200):null,error_code:errorMessage?"provider_delivery_failed":null,error_message:errorMessage};
   const saved=await db(url,key,"mme_security_notification_delivery_attempts","POST",attempt);
   if(!saved.ok){results.push({id:n.notification_id,status:"receipt_write_failed"});continue;}
   const failed=status==="failed",delay=Math.min(3600000,30000*2**Math.max(0,n.delivery_attempts-1));
   const patch:any={status:failed?"failed":"sent",last_error:errorMessage,last_delivery_status:status,provider_reference:attempt.provider_reference,delivery_claimed_at:null,delivery_lease_expires_at:null,next_attempt_at:failed&&n.delivery_attempts<n.delivery_max_attempts?new Date(Date.now()+delay).toISOString():null};
   if(status==="delivered")patch.delivered_at=new Date().toISOString();
   const savedState=await db(url,key,"mme_security_incident_notifications?notification_id=eq."+encodeURIComponent(n.notification_id),"PATCH",patch);
   if(!savedState.ok){results.push({id:n.notification_id,status:"state_update_failed"});continue;}
   if(failed&&n.delivery_attempts>=n.delivery_max_attempts){const dead=await db(url,key,"rpc/mme_security_notification_quarantine","POST",{p_notification:n.notification_id,p_reason:errorMessage??"retry budget exhausted",p_provider:attempt.provider});results.push({id:n.notification_id,status:dead.ok?"dead_lettered":"dead_letter_failed"});continue;}
   results.push({id:n.notification_id,status});
  } catch {
   const errorMessage="provider_unreachable";
   const attempt={notification_id:n.notification_id,attempt_number:n.delivery_attempts,channel:n.channel,provider:"mme-webhook-adapter",status:"failed",error_code:errorMessage,error_message:errorMessage};
   const saved=await db(url,key,"mme_security_notification_delivery_attempts","POST",attempt);
   const delay=Math.min(3600000,30000*2**Math.max(0,n.delivery_attempts-1));
   await db(url,key,"mme_security_incident_notifications?notification_id=eq."+encodeURIComponent(n.notification_id),"PATCH",{status:"failed",last_error:errorMessage,last_delivery_status:"failed",delivery_claimed_at:null,delivery_lease_expires_at:null,next_attempt_at:n.delivery_attempts<n.delivery_max_attempts?new Date(Date.now()+delay).toISOString():null});
   if(saved.ok&&n.delivery_attempts>=n.delivery_max_attempts) await db(url,key,"rpc/mme_security_notification_quarantine","POST",{p_notification:n.notification_id,p_reason:errorMessage,p_provider:"mme-webhook-adapter"});
   results.push({id:n.notification_id,status:saved.ok?"retry_or_dead_letter":"receipt_write_failed"});
  }
 }
 return NextResponse.json({requestId,claimed:rows.length,results},{headers:{"Cache-Control":"no-store"}});
}