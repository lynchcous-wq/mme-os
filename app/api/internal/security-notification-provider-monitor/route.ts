import { NextRequest, NextResponse } from "next/server";
import { randomUUID, timingSafeEqual } from "node:crypto";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const channels = ["email","sms","pager","push"];
function authorized(req:NextRequest) {
 const expected=process.env.MME_NOTIFICATION_HEALTHCHECK_SECRET??"";
 const supplied=req.headers.get("x-mme-notification-healthcheck-secret")??"";
 if(!expected||!supplied)return false;
 const a=Buffer.from(expected),b=Buffer.from(supplied);
 return a.length===b.length&&timingSafeEqual(a,b);
}
async function db(url:string,key:string,path:string,body:unknown) {
 return fetch(url+"/rest/v1/"+path,{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json",Prefer:"return=representation"},body:JSON.stringify(body),cache:"no-store"});
}
export async function POST(req:NextRequest) {
 const requestId=randomUUID();
 if(!authorized(req))return NextResponse.json({error:"monitor_authentication_required",requestId},{status:401});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)return NextResponse.json({error:"monitor_configuration_missing",requestId},{status:503});
 const b=await req.json().catch(()=>null);
 if(!b||typeof b.provider!=="string"||b.provider.length>80||!channels.includes(b.channel)||typeof b.healthy!=="boolean")return NextResponse.json({error:"invalid_probe_result",requestId},{status:400});
 const latency=b.latencyMs==null?null:Number(b.latencyMs),status=b.statusCode==null?null:Number(b.statusCode);
 if(latency!==null&&(!Number.isInteger(latency)||latency<0||latency>600000))return NextResponse.json({error:"invalid_latency",requestId},{status:400});
 if(status!==null&&(!Number.isInteger(status)||status<100||status>599))return NextResponse.json({error:"invalid_status_code",requestId},{status:400});
 const recorded=await db(url,key,"rpc/mme_security_notification_record_health",{p_provider:b.provider,p_channel:b.channel,p_healthy:b.healthy,p_latency_ms:latency,p_status_code:status,p_error_code:typeof b.errorCode==="string"?b.errorCode.slice(0,80):null,p_details:typeof b.details==="string"?b.details.slice(0,500):null});
 if(!recorded.ok)return NextResponse.json({error:"health_record_failed",requestId},{status:502});
 const health=(await recorded.json())?.[0]??null;
 if(!health)return NextResponse.json({error:"health_record_empty",requestId},{status:502});
 if(b.healthy) {
  const recovered=await db(url,key,"rpc/mme_security_notification_recover_outage",{p_provider:b.provider,p_channel:b.channel});
  if(!recovered.ok)return NextResponse.json({error:"outage_recovery_failed",requestId},{status:502});
  return NextResponse.json({requestId,recorded:true,circuitState:health.circuit_state,recovered:Number(await recovered.json())||0},{headers:{"Cache-Control":"no-store"}});
 }
 const severity=Number(health.consecutive_failures)>=5?"critical":Number(health.consecutive_failures)>=3?"high":"medium";
 const outage=await db(url,key,"rpc/mme_security_notification_record_outage",{p_provider:b.provider,p_channel:b.channel,p_outage_key:b.provider+":"+b.channel+":active",p_severity:severity,p_summary:typeof b.details==="string"?b.details.slice(0,1000):"Provider health probe failed"});
 if(!outage.ok)return NextResponse.json({error:"outage_record_failed",requestId},{status:502});
 return NextResponse.json({requestId,recorded:true,circuitState:health.circuit_state,consecutiveFailures:health.consecutive_failures,outage:(await outage.json())?.[0]??null},{headers:{"Cache-Control":"no-store"}});
}
