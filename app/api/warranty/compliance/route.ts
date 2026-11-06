import { NextRequest, NextResponse } from "next/server";
import { createHash, randomUUID } from "node:crypto";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const VIEWS={summary:"mme_warranty_compliance_dashboard_kpis",calendar:"mme_warranty_compliance_retention_calendar",approvals:"mme_warranty_compliance_approval_queue",alerts:"mme_warranty_compliance_alert_feed",assignments:"mme_warranty_compliance_department_summary"} as const;
type Resource=keyof typeof VIEWS; type Role="ceo"|"privacy_officer"|"manager"|"warranty_specialist";
const ACCESS:Record<Resource,Role[]>={summary:["ceo","privacy_officer","manager"],calendar:["ceo","privacy_officer","manager","warranty_specialist"],approvals:["ceo","privacy_officer","manager"],alerts:["ceo","privacy_officer","manager","warranty_specialist"],assignments:["ceo","privacy_officer","manager"]};
const hash=(s:string)=>createHash("sha256").update(s).digest("hex");
const response=(status:number,error:string,id:string)=>NextResponse.json({error,requestId:id},{status,headers:{"Cache-Control":"no-store","X-Request-ID":id}});
async function rpc(url:string,key:string,name:string,body:unknown){const r=await fetch(url+"/rest/v1/rpc/"+name,{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify(body),cache:"no-store"});if(!r.ok)throw new Error("rpc_failed");return r.json().catch(()=>null);}
function rolesOf(user:any):Role[]{const r=user?.app_metadata?.roles??(user?.app_metadata?.role?[user.app_metadata.role]:[]);return Array.isArray(r)?r.filter((x):x is Role=>["ceo","privacy_officer","manager","warranty_specialist"].includes(x)):[];}
export async function GET(req:NextRequest){
 const id=randomUUID(),url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!anon||!key)return response(503,"compliance_api_not_configured",id);
 const raw=req.nextUrl.searchParams.get("resource")??"unknown",resource=raw in VIEWS?raw as Resource:null;
 const ip=req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()??req.headers.get("x-real-ip")??"unknown",ipHash=hash(ip);
 const token=(req.headers.get("authorization")??"").match(/^Bearer\s+(.+)$/i)?.[1];
 let user:any=null;if(token){const a=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);if(a?.ok)user=await a.json().catch(()=>null);}
 const roleList=user?rolesOf(user):[];
 const record=async(type:string,severity:string,reason:string,actorId:string|null,role:string|null)=>rpc(url,key,"mme_warranty_api_record_security_event",{p_event_key:hash([type,actorId??"anonymous",ipHash,reason].join("|")),p_request_id:id,p_actor_id:actorId,p_event_type:type,p_severity:severity,p_resource:resource??"unknown",p_actor_role:role,p_ip_digest:ipHash,p_reason_code:reason});
 if(!user?.id){await record("authentication_failure","warning",token?"invalid_session":"authentication_required",null,null).catch(()=>null);return response(401,token?"invalid_session":"authentication_required",id);}
 if(!resource){await record("api_error","info","invalid_resource",user.id,roleList[0]??null).catch(()=>null);return response(400,"invalid_resource",id);}
 if(!roleList.some(r=>ACCESS[resource].includes(r))){await record("authorization_denial","high","insufficient_permissions",user.id,roleList[0]??null).catch(()=>null);return response(403,"insufficient_permissions",id);}
 try{
  const [u,i]=await Promise.all([
   rpc(url,key,"mme_warranty_compliance_consume_rate_limit",{p_bucket_key:hash("user:"+user.id),p_limit:60,p_window_seconds:60}),
   rpc(url,key,"mme_warranty_compliance_consume_rate_limit",{p_bucket_key:hash("ip:"+ipHash),p_limit:180,p_window_seconds:60})
  ]);
  const allowed=(Array.isArray(u)?u[0]?.allowed:u?.allowed)&&(Array.isArray(i)?i[0]?.allowed:i?.allowed);
  if(!allowed){await record("rate_limit_exceeded","high","rate_limit_exceeded",user.id,roleList[0]??null).catch(()=>null);return response(429,"rate_limit_exceeded",id);}
 }catch{await record("api_error","critical","rate_limit_infrastructure_unavailable",user.id,roleList[0]??null).catch(()=>null);return response(503,"compliance_api_temporarily_unavailable",id);}
 const dataResponse=await fetch(url+"/rest/v1/"+VIEWS[resource]+"?select=*",{headers:{apikey:key,Authorization:"Bearer "+key,Accept:"application/json"},cache:"no-store"}).catch(()=>null);
 if(!dataResponse?.ok){await record("api_error","high","compliance_data_unavailable",user.id,roleList[0]??null).catch(()=>null);return response(502,"compliance_data_unavailable",id);}
 const data=await dataResponse.json().catch(()=>null);if(!Array.isArray(data)){await record("api_error","high","invalid_compliance_response",user.id,roleList[0]??null).catch(()=>null);return response(502,"invalid_compliance_response",id);}
 return NextResponse.json({requestId:id,resource,data:data.slice(0,500),count:Math.min(data.length,500),truncated:data.length>500,asOf:new Date().toISOString()},{headers:{"Cache-Control":"no-store","Vary":"Authorization","X-Request-ID":id}});
}
