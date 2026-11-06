import {NextRequest,NextResponse} from "next/server";
import {createHash,randomUUID} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
const VIEWS={kpis:"mme_warranty_api_security_executive_kpis",incidents:"mme_warranty_api_security_executive_incidents",activity:"mme_warranty_api_security_executive_activity",events:"mme_warranty_api_security_executive_event_feed"} as const;
type Resource=keyof typeof VIEWS;type Role="ceo"|"privacy_officer"|"manager";
const hash=(s:string)=>createHash("sha256").update(s).digest("hex");
const reply=(status:number,error:string,id:string)=>NextResponse.json({error,requestId:id},{status,headers:{"Cache-Control":"no-store","X-Request-ID":id}});
export async function GET(req:NextRequest){
 const id=randomUUID(),url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!anon||!key)return reply(503,"security_cockpit_not_configured",id);
 const token=(req.headers.get("authorization")??"").match(/^Bearer\\s+(.+)$/i)?.[1];
 if(!token)return reply(401,"authentication_required",id);
 const auth=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);
 if(!auth?.ok)return reply(401,"invalid_session",id);
 const user=await auth.json().catch(()=>null),raw=user?.app_metadata?.roles??(user?.app_metadata?.role?[user.app_metadata.role]:[]);
 const roles:Role[]=Array.isArray(raw)?raw.filter((r):r is Role=>["ceo","privacy_officer","manager"].includes(r)):[];
 if(!roles.length)return reply(403,"security_cockpit_access_denied",id);
 const resource=req.nextUrl.searchParams.get("resource") as Resource;
 if(!(resource in VIEWS))return reply(400,"invalid_resource",id);
 const limit=Math.min(500,Math.max(1,Number(req.nextUrl.searchParams.get("limit")??100)||100));
 const result=await fetch(url+"/rest/v1/"+VIEWS[resource]+"?select=*&limit="+limit,{headers:{apikey:key,Authorization:"Bearer "+key,Accept:"application/json"},cache:"no-store"}).catch(()=>null);
 if(!result?.ok)return reply(502,"security_data_unavailable",id);
 const data=await result.json().catch(()=>null);if(!Array.isArray(data))return reply(502,"invalid_security_response",id);
 return NextResponse.json({requestId:id,resource,data,count:data.length,asOf:new Date().toISOString()},{headers:{"Cache-Control":"no-store","Vary":"Authorization","X-Request-ID":id}});
}
export async function POST(req:NextRequest){
 const id=randomUUID(),url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!anon||!key)return reply(503,"security_cockpit_not_configured",id);
 const token=(req.headers.get("authorization")??"").match(/^Bearer\\s+(.+)$/i)?.[1];if(!token)return reply(401,"authentication_required",id);
 const auth=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);
 if(!auth?.ok)return reply(401,"invalid_session",id);
 const user=await auth.json().catch(()=>null),raw=user?.app_metadata?.roles??(user?.app_metadata?.role?[user.app_metadata.role]:[]);
 const roles=Array.isArray(raw)?raw:[];
 if(!roles.some(r=>["ceo","privacy_officer","manager"].includes(r)))return reply(403,"security_cockpit_access_denied",id);
 let body:any;try{body=await req.json();}catch{return reply(400,"invalid_json",id);}
 if(!body||typeof body!=="object"||Array.isArray(body)||Object.keys(body).some(k=>!["action","incidentId","note"].includes(k)))return reply(400,"invalid_request",id);
 if(body.action!=="acknowledge"||typeof body.incidentId!=="string"||!/^[0-9a-f-]{36}$/i.test(body.incidentId)||typeof body.note!=="string"||body.note.length>500)return reply(400,"invalid_action",id);
 const result=await fetch(url+"/rest/v1/rpc/mme_warranty_api_acknowledge_security_incident",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify({p_incident_id:body.incidentId,p_actor_id:user.id,p_note:body.note}),cache:"no-store"}).catch(()=>null);
 if(!result?.ok)return reply(409,"incident_acknowledgement_failed",id);
 return NextResponse.json({ok:true,requestId:id},{headers:{"Cache-Control":"no-store"}});
}
