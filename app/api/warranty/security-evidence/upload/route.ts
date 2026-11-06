import {NextRequest,NextResponse} from "next/server";
import {createHash,randomUUID} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
const MAX=25*1024*1024,BUCKET="mme-security-evidence-quarantine";
const MIME=new Set(["application/pdf","image/jpeg","image/png","image/webp","text/plain","text/csv","application/json","video/mp4"]);
const ROLES=["ceo","privacy_officer","manager"];
const reply=(status:number,error:string,id:string)=>NextResponse.json({error,requestId:id},{status,headers:{"Cache-Control":"no-store","X-Request-ID":id}});
function detected(bytes:Buffer):string|null{
 if(bytes.subarray(0,5).toString()==="%PDF-")return "application/pdf";
 if(bytes.length>=3&&bytes[0]===0xff&&bytes[1]===0xd8&&bytes[2]===0xff)return "image/jpeg";
 if(bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))return "image/png";
 if(bytes.subarray(0,4).toString()==="RIFF"&&bytes.subarray(8,12).toString()==="WEBP")return "image/webp";
 if(bytes.length>=12&&bytes.subarray(4,8).toString()==="ftyp")return "video/mp4";
 if(bytes.subarray(0,Math.min(bytes.length,4096)).includes(0))return null;
 return "text";
}
async function identity(req:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 const token=(req.headers.get("authorization")??"").match(/^Bearer\s+(.+)$/i)?.[1];if(!url||!anon||!key||!token)return null;
 const r=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);if(!r?.ok)return null;
 const user=await r.json().catch(()=>null),roles=user?.app_metadata?.roles??(user?.app_metadata?.role?[user.app_metadata.role]:[]);
 return user?.id&&Array.isArray(roles)&&roles.some((x:string)=>ROLES.includes(x))?{url,anon,key,user}:null;
}
export async function POST(req:NextRequest){
 const id=randomUUID(),auth=await identity(req);if(!auth)return reply(401,"authentication_or_role_required",id);
 let form:FormData;try{form=await req.formData();}catch{return reply(400,"invalid_multipart_upload",id);}
 const file=form.get("file"),caseId=form.get("caseId"),evidenceType=form.get("evidenceType"),description=form.get("description");
 if(!(file instanceof File)||typeof caseId!=="string"||!/^[0-9a-f-]{36}$/i.test(caseId)||typeof evidenceType!=="string"||!["document","image","video","log","transaction","device","other"].includes(evidenceType))return reply(400,"invalid_upload_fields",id);
 if(file.size<1||file.size>MAX)return reply(413,"file_size_limit_exceeded",id);
 const declared=file.type.toLowerCase();if(!MIME.has(declared))return reply(415,"unsupported_media_type",id);
 const bytes=Buffer.from(await file.arrayBuffer());if(bytes.length!==file.size)return reply(400,"upload_size_mismatch",id);
 const kind=detected(bytes),expected=declared==="text/plain"||declared==="text/csv"||declared==="application/json"?"text":declared;
 if(kind!==expected)return reply(415,"file_signature_mismatch",id);
 const digest=createHash("sha256").update(bytes).digest("hex"),objectId=randomUUID(),path=caseId+"/"+objectId;
 const upload=await fetch(auth.url+"/storage/v1/object/"+BUCKET+"/"+path,{method:"POST",headers:{apikey:auth.key,Authorization:"Bearer "+auth.key,"Content-Type":declared,"x-upsert":"false"},body:bytes,cache:"no-store"}).catch(()=>null);
 if(!upload?.ok)return reply(502,"private_storage_upload_failed",id);
 const rpc=await fetch(auth.url+"/rest/v1/rpc/mme_warranty_api_security_evidence_register_upload",{method:"POST",headers:{apikey:auth.key,Authorization:"Bearer "+auth.key,"Content-Type":"application/json"},body:JSON.stringify({p_case_id:caseId,p_actor_id:auth.user.id,p_evidence_type:evidenceType,p_bucket:BUCKET,p_path:path,p_filename:file.name.slice(0,255),p_content_type:declared,p_byte_size:bytes.length,p_sha256:digest,p_description:typeof description==="string"?description.slice(0,2000):""}),cache:"no-store"}).catch(()=>null);
 if(!rpc?.ok){await fetch(auth.url+"/storage/v1/object/"+BUCKET+"/"+path,{method:"DELETE",headers:{apikey:auth.key,Authorization:"Bearer "+auth.key},cache:"no-store"}).catch(()=>null);return reply(409,"evidence_registration_failed",id);}
 const evidenceId=await rpc.json().catch(()=>null);
 return NextResponse.json({ok:true,requestId:id,evidenceId,sha256:digest,byteSize:bytes.length,status:"pending_scan"},{status:201,headers:{"Cache-Control":"no-store","X-Request-ID":id}});
}
