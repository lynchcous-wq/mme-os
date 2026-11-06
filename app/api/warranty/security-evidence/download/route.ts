import {NextRequest,NextResponse} from "next/server";
import {randomUUID} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
const roles=["ceo","privacy_officer","manager"];
const fail=(status:number,error:string,id:string)=>NextResponse.json({error,requestId:id},{status,headers:{"Cache-Control":"no-store","X-Request-ID":id}});
async function auth(req:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,key=process.env.SUPABASE_SERVICE_ROLE_KEY,token=(req.headers.get("authorization")??"").match(/^Bearer\s+(.+)$/i)?.[1];
 if(!url||!anon||!key||!token)return null;
 const r=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);if(!r?.ok)return null;
 const user=await r.json().catch(()=>null),claims=user?.app_metadata?.roles??(user?.app_metadata?.role?[user.app_metadata.role]:[]);
 if(!user?.id||!Array.isArray(claims))return null;const allowed=claims.filter((x:string)=>roles.includes(x));
 return allowed.length?{url,key,user,roles:allowed}:null;
}
export async function GET(req:NextRequest){
 const id=randomUUID(),a=await auth(req);if(!a)return fail(401,"authentication_or_role_required",id);
 const evidenceId=req.nextUrl.searchParams.get("evidenceId");if(!evidenceId||!/^[0-9a-f-]{36}$/i.test(evidenceId))return fail(400,"invalid_evidence_id",id);
 const rpc=await fetch(a.url+"/rest/v1/rpc/mme_warranty_api_security_evidence_authorize_download",{method:"POST",headers:{apikey:a.key,Authorization:"Bearer "+a.key,"Content-Type":"application/json"},body:JSON.stringify({p_evidence_id:evidenceId,p_actor_id:a.user.id,p_roles:a.roles,p_request_id:id}),cache:"no-store"}).catch(()=>null);
 if(!rpc?.ok)return fail(403,"evidence_access_denied",id);
 const rows=await rpc.json().catch(()=>null),row=Array.isArray(rows)?rows[0]:null;if(!row?.allowed)return fail(403,"evidence_access_denied",id);
 const object=await fetch(a.url+"/storage/v1/object/"+encodeURIComponent(row.storage_bucket)+"/"+row.storage_path.split("/").map(encodeURIComponent).join("/"),{headers:{apikey:a.key,Authorization:"Bearer "+a.key},cache:"no-store"}).catch(()=>null);
 if(!object?.ok)return fail(502,"evidence_object_unavailable",id);
 const bytes=await object.arrayBuffer();
 return new NextResponse(bytes,{status:200,headers:{"Content-Type":row.content_type??"application/octet-stream","Content-Length":String(bytes.byteLength),"Content-Disposition":'attachment; filename="evidence-'+evidenceId+'"',"Cache-Control":"private, no-store","X-Content-Type-Options":"nosniff","X-Request-ID":id}});
}
