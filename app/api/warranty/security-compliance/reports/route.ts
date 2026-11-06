import {NextRequest,NextResponse} from "next/server";
import {randomUUID} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
const VIEWS={summary:"mme_warranty_security_compliance_kpis",evidence:"mme_warranty_security_compliance_evidence",access:"mme_warranty_security_compliance_access",holds:"mme_warranty_security_compliance_holds",retention:"mme_warranty_security_compliance_retention",custody:"mme_warranty_security_compliance_custody"} as const;
type Resource=keyof typeof VIEWS;type Role="ceo"|"privacy_officer"|"manager"|"warranty_specialist";
const ACCESS:Record<Resource,Role[]>={summary:["ceo","privacy_officer","manager"],evidence:["ceo","privacy_officer","manager","warranty_specialist"],access:["ceo","privacy_officer"],holds:["ceo","privacy_officer","manager"],retention:["ceo","privacy_officer","manager"],custody:["ceo","privacy_officer","manager","warranty_specialist"]};
const send=(status:number,error:string,id:string)=>NextResponse.json({error,requestId:id},{status,headers:{"Cache-Control":"no-store","X-Request-ID":id}});
function roleList(user:any):Role[]{const r=user?.app_metadata?.roles??(user?.app_metadata?.role?[user.app_metadata.role]:[]);return Array.isArray(r)?r.filter((x):x is Role=>["ceo","privacy_officer","manager","warranty_specialist"].includes(x)):[];}
export async function GET(req:NextRequest){
 const id=randomUUID(),url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!anon||!key)return send(503,"compliance_reporting_not_configured",id);
 const token=(req.headers.get("authorization")??"").match(/^Bearer\s+(.+)$/i)?.[1];if(!token)return send(401,"authentication_required",id);
 const session=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);
 if(!session?.ok)return send(401,"invalid_session",id);
 const user=await session.json().catch(()=>null),roles=roleList(user),raw=req.nextUrl.searchParams.get("resource")??"summary",resource=raw in VIEWS?raw as Resource:null;
 if(!user?.id)return send(401,"invalid_session",id);
 if(!resource)return send(400,"invalid_resource",id);
 const role=roles.find(r=>ACCESS[resource].includes(r));
 const audit=async(outcome:"granted"|"denied"|"failed")=>fetch(url+"/rest/v1/mme_warranty_security_compliance_report_events",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json",Prefer:"return=minimal"},body:JSON.stringify({actor_id:user.id,actor_role:roles[0]??"manager",report_resource:resource,outcome,request_id:id}),cache:"no-store"}).catch(()=>null);
 if(!role){if(roles.length)await audit("denied");return send(403,"insufficient_permissions",id);}
 const limitRaw=Number(req.nextUrl.searchParams.get("limit")??100),limit=Number.isInteger(limitRaw)?Math.max(1,Math.min(500,limitRaw)):100;
 const offsetRaw=Number(req.nextUrl.searchParams.get("offset")??0),offset=Number.isInteger(offsetRaw)?Math.max(0,Math.min(1000000,offsetRaw)):0;
 const response=await fetch(url+"/rest/v1/"+VIEWS[resource]+"?select=*&limit="+limit+"&offset="+offset,{headers:{apikey:key,Authorization:"Bearer "+key,Accept:"application/json"},cache:"no-store"}).catch(()=>null);
 if(!response?.ok){await audit("failed");return send(502,"compliance_report_query_failed",id);}
 const data=await response.json().catch(()=>null);if(!Array.isArray(data)){await audit("failed");return send(502,"invalid_compliance_report",id);}
 await audit("granted");
 return NextResponse.json({requestId:id,resource,data,count:data.length,limit,offset,asOf:new Date().toISOString()},{headers:{"Cache-Control":"no-store","Vary":"Authorization","X-Request-ID":id}});
}
