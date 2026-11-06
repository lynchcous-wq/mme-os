import {NextRequest,NextResponse} from "next/server";
import {randomUUID} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
const roles=["ceo","privacy_officer","manager"] as const;
const response=(status:number,error:string,id:string)=>NextResponse.json({error,requestId:id},{status,headers:{"Cache-Control":"no-store","X-Request-ID":id}});
async function identity(req:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 const token=(req.headers.get("authorization")??"").match(/^Bearer\\s+(.+)$/i)?.[1];
 if(!url||!anon||!key||!token)return null;
 const auth=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);
 if(!auth?.ok)return null;
 const user=await auth.json().catch(()=>null),raw=user?.app_metadata?.roles??(user?.app_metadata?.role?[user.app_metadata.role]:[]);
 return user?.id&&Array.isArray(raw)&&raw.some((r:string)=>roles.includes(r as typeof roles[number]))?{url,key,user}:null;
}
export async function POST(req:NextRequest){
 const id=randomUUID(),auth=await identity(req);if(!auth)return response(401,"authentication_or_role_required",id);
 let b:any;try{b=await req.json();}catch{return response(400,"invalid_json",id);}
 if(!b||typeof b!=="object"||Array.isArray(b)||typeof b.action!=="string")return response(400,"invalid_request",id);
 const actor=auth.user.id;let fn="",args:any={};
 switch(b.action){
 case "create":
  if(typeof b.incidentId!=="string"||typeof b.title!=="string"||typeof b.priority!=="string")return response(400,"invalid_case_fields",id);
  fn="mme_warranty_api_security_case_create";args={p_incident_id:b.incidentId,p_title:b.title,p_summary:typeof b.summary==="string"?b.summary:"",p_priority:b.priority,p_actor_id:actor,p_due_at:b.dueAt??null};break;
 case "assign":
  if(typeof b.caseId!=="string"||typeof b.investigatorId!=="string")return response(400,"invalid_assignment",id);
  fn="mme_warranty_api_security_case_assign";args={p_case_id:b.caseId,p_investigator_id:b.investigatorId,p_actor_id:actor,p_reason:typeof b.reason==="string"?b.reason:""};break;
 case "note":
  if(typeof b.caseId!=="string"||typeof b.body!=="string")return response(400,"invalid_note",id);
  fn="mme_warranty_api_security_case_add_note";args={p_case_id:b.caseId,p_actor_id:actor,p_note_type:b.noteType??"investigation",p_body:b.body};break;
 case "evidence":
  for(const k of ["caseId","evidenceType","bucket","path","sha256"])if(typeof b[k]!=="string")return response(400,"invalid_evidence",id);
  fn="mme_warranty_api_security_case_add_evidence";args={p_case_id:b.caseId,p_actor_id:actor,p_evidence_type:b.evidenceType,p_bucket:b.bucket,p_path:b.path,p_filename:b.filename??null,p_content_type:b.contentType??null,p_byte_size:b.byteSize??null,p_sha256:b.sha256,p_description:b.description??""};break;
 case "custody":
  for(const k of ["evidenceId","toCustodian","sha256","reason"])if(typeof b[k]!=="string")return response(400,"invalid_custody_transfer",id);
  fn="mme_warranty_api_security_case_transfer_custody";args={p_evidence_id:b.evidenceId,p_from:b.fromCustodian??null,p_to:b.toCustodian,p_actor_id:actor,p_reason:b.reason,p_sha256:b.sha256};break;
 case "status":
  if(typeof b.caseId!=="string"||typeof b.status!=="string")return response(400,"invalid_status_change",id);
  fn="mme_warranty_api_security_case_set_status";args={p_case_id:b.caseId,p_status:b.status,p_actor_id:actor,p_reason:b.reason??"",p_closure_code:b.closureCode??null};break;
 default:return response(400,"unsupported_action",id);
 }
 const r=await fetch(auth.url+"/rest/v1/rpc/"+fn,{method:"POST",headers:{apikey:auth.key,Authorization:"Bearer "+auth.key,"Content-Type":"application/json"},body:JSON.stringify(args),cache:"no-store"}).catch(()=>null);
 if(!r?.ok)return response(409,"investigation_action_failed",id);
 const data=await r.json().catch(()=>null);
 return NextResponse.json({ok:true,requestId:id,data},{headers:{"Cache-Control":"no-store","X-Request-ID":id}});
}
