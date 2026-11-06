import {NextRequest,NextResponse} from "next/server";
import {randomUUID} from "node:crypto";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const READ=new Set(["ceo","cio","it_admin","privacy_officer","manager"]);
const WRITE=new Set(["ceo","cio","it_admin"]);
async function auth(req:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,service=process.env.SUPABASE_SERVICE_ROLE_KEY;
 const token=(req.headers.get("authorization")??"").match(/^Bearer\s+(.+)$/i)?.[1];
 if(!url||!anon||!service)return {error:"configuration_missing",status:503 as const};
 if(!token)return {error:"authentication_required",status:401 as const};
 const r=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);
 if(!r?.ok)return {error:"invalid_session",status:401 as const};
 const user=await r.json(),roles=user?.app_metadata?.roles??[user?.app_metadata?.role];
 if(!Array.isArray(roles))return {error:"access_denied",status:403 as const};
 const role=roles.find((x:string)=>WRITE.has(x))??roles.find((x:string)=>READ.has(x));
 if(!role)return {error:"access_denied",status:403 as const};
 return {url,service,user,role};
}
export async function GET(req:NextRequest){
 const requestId=randomUUID(),c=await auth(req);
 if("error" in c)return NextResponse.json({error:c.error,requestId},{status:c.status});
 const headers={apikey:c.service,Authorization:"Bearer "+c.service};
 const [s,a,h]=await Promise.all([
  fetch(c.url+"/rest/v1/rpc/mme_security_monitoring_capture_snapshot",{method:"POST",headers:{...headers,"Content-Type":"application/json"},body:"{}",cache:"no-store"}).catch(()=>null),
  fetch(c.url+"/rest/v1/mme_security_integration_alerts?select=alert_id,source_system,severity,status,metric_name,metric_value,threshold,message,opened_at,acknowledged_at,resolved_at&order=opened_at.desc&limit=100",{headers,cache:"no-store"}).catch(()=>null),
  fetch(c.url+"/rest/v1/mme_security_executive_action_audit?select=audit_id,actor_id,actor_role,action,target_alert_id,rationale,created_at&order=created_at.desc&limit=25",{headers,cache:"no-store"}).catch(()=>null)
 ]);
 if(!s?.ok||!a?.ok||!h?.ok)return NextResponse.json({error:"executive_data_unavailable",requestId},{status:502});
 const [snapshot,alerts,audit]=await Promise.all([s.json(),a.json(),h.json()]);
 return NextResponse.json({requestId,role:c.role,snapshot,alerts,audit},{headers:{"Cache-Control":"no-store","X-Request-ID":requestId}});
}
export async function POST(req:NextRequest){
 const requestId=randomUUID(),c=await auth(req);
 if("error" in c)return NextResponse.json({error:c.error,requestId},{status:c.status});
 if(!WRITE.has(c.role))return NextResponse.json({error:"executive_action_forbidden",requestId},{status:403});
 let b:any;try{b=await req.json()}catch{return NextResponse.json({error:"invalid_json",requestId},{status:400})}
 const id=typeof b?.alertId==="string"?b.alertId:"",action=typeof b?.action==="string"?b.action:"",rationale=typeof b?.rationale==="string"?b.rationale.trim():"";
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)||!["acknowledge_alert","resolve_alert"].includes(action)||rationale.length<10||rationale.length>2000)
  return NextResponse.json({error:"invalid_action_request",requestId},{status:400});
 const result=await fetch(c.url+"/rest/v1/rpc/mme_security_executive_record_action",{method:"POST",headers:{apikey:c.service,Authorization:"Bearer "+c.service,"Content-Type":"application/json"},body:JSON.stringify({p_alert_id:id,p_action:action,p_actor_id:c.user.id,p_actor_role:c.role,p_rationale:rationale,p_request_id:requestId}),cache:"no-store"}).catch(()=>null);
 if(!result?.ok)return NextResponse.json({error:"executive_action_not_recorded",requestId},{status:409});
 return NextResponse.json({requestId,result:await result.json()},{headers:{"Cache-Control":"no-store","X-Request-ID":requestId}});
}