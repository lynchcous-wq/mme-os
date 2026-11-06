import {NextRequest,NextResponse} from "next/server";
import {randomUUID} from "node:crypto";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const ROLES=new Set(["ceo","cio","it_admin","manager"]);
async function auth(req:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,service=process.env.SUPABASE_SERVICE_ROLE_KEY;
 const token=(req.headers.get("authorization")??"").match(/^Bearer\s+(.+)$/i)?.[1];
 if(!url||!anon||!service)return {error:"configuration_missing",status:503 as const};
 if(!token)return {error:"authentication_required",status:401 as const};
 const r=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);
 if(!r?.ok)return {error:"invalid_session",status:401 as const};
 const user=await r.json(),roles=user?.app_metadata?.roles??[user?.app_metadata?.role];
 if(!Array.isArray(roles))return {error:"access_denied",status:403 as const};
 const role=roles.find((x:string)=>ROLES.has(x));
 if(!role)return {error:"access_denied",status:403 as const};
 return {url,service,user,role};
}
export async function GET(req:NextRequest){
 const requestId=randomUUID(),c=await auth(req);
 if("error" in c)return NextResponse.json({error:c.error,requestId},{status:c.status});
 const headers={apikey:c.service,Authorization:"Bearer "+c.service};
 const [cases,events]=await Promise.all([
 fetch(c.url+"/rest/v1/mme_security_incident_response_cases?select=*&order=sla_due_at.asc&limit=200",{headers,cache:"no-store"}).catch(()=>null),
 fetch(c.url+"/rest/v1/mme_security_incident_response_events?select=*&order=created_at.desc&limit=100",{headers,cache:"no-store"}).catch(()=>null)
 ]);
 if(!cases?.ok||!events?.ok)return NextResponse.json({error:"incident_response_data_unavailable",requestId},{status:502});
 return NextResponse.json({requestId,role:c.role,cases:await cases.json(),events:await events.json()},{headers:{"Cache-Control":"no-store","X-Request-ID":requestId}});
}
export async function POST(req:NextRequest){
 const requestId=randomUUID(),c=await auth(req);
 if("error" in c)return NextResponse.json({error:c.error,requestId},{status:c.status});
 let b:any;try{b=await req.json()}catch{return NextResponse.json({error:"invalid_json",requestId},{status:400})}
 const alertId=typeof b?.alertId==="string"?b.alertId:"",action=typeof b?.action==="string"?b.action:"",rationale=typeof b?.rationale==="string"?b.rationale.trim():"";
 const ownerId=typeof b?.ownerId==="string"?b.ownerId:null,recoveryEvidence=typeof b?.recoveryEvidence==="string"?b.recoveryEvidence.trim():null;
 const actions=["open_case","assign_owner","escalate","verify_recovery","request_closure","approve_closure"];
 const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
 if(!uuid.test(alertId)||!actions.includes(action)||rationale.length<10||rationale.length>2000||(ownerId&&!uuid.test(ownerId))||(recoveryEvidence!==null&&(recoveryEvidence.length<10||recoveryEvidence.length>2000)))
  return NextResponse.json({error:"invalid_action_request",requestId},{status:400});
 const result=await fetch(c.url+"/rest/v1/rpc/mme_security_incident_response_action",{method:"POST",headers:{apikey:c.service,Authorization:"Bearer "+c.service,"Content-Type":"application/json"},body:JSON.stringify({p_alert_id:alertId,p_action:action,p_actor_id:c.user.id,p_actor_role:c.role,p_rationale:rationale,p_owner_id:ownerId,p_recovery_evidence:recoveryEvidence,p_request_id:requestId}),cache:"no-store"}).catch(()=>null);
 if(!result?.ok)return NextResponse.json({error:"incident_response_action_not_recorded",requestId},{status:409});
 return NextResponse.json({requestId,result:await result.json()},{headers:{"Cache-Control":"no-store","X-Request-ID":requestId}});
}