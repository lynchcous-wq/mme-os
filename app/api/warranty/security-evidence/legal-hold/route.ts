import {NextRequest,NextResponse} from "next/server";
import {randomUUID} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
const roles=["ceo","privacy_officer"];
const out=(status:number,error:string,id:string)=>NextResponse.json({error,requestId:id},{status,headers:{"Cache-Control":"no-store","X-Request-ID":id}});
export async function POST(req:NextRequest){
 const id=randomUUID(),url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,key=process.env.SUPABASE_SERVICE_ROLE_KEY,token=(req.headers.get("authorization")??"").match(/^Bearer\s+(.+)$/i)?.[1];
 if(!url||!anon||!key||!token)return out(401,"authentication_required",id);
 const session=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);if(!session?.ok)return out(401,"invalid_session",id);
 const user=await session.json().catch(()=>null),claims=user?.app_metadata?.roles??(user?.app_metadata?.role?[user.app_metadata.role]:[]);
 if(!user?.id||!Array.isArray(claims)||!claims.some((r:string)=>roles.includes(r)))return out(403,"legal_hold_admin_required",id);
 let b:any;try{b=await req.json();}catch{return out(400,"invalid_json",id);}
 if(!b||typeof b!=="object"||Array.isArray(b))return out(400,"invalid_request",id);
 let fn:string,args:any;
 if(b.action==="place"&&typeof b.evidenceId==="string"&&typeof b.reason==="string"&&b.reason.trim().length>=5){fn="mme_warranty_api_security_evidence_place_hold";args={p_evidence_id:b.evidenceId,p_actor_id:user.id,p_reason:b.reason};}
 else if(b.action==="release"&&typeof b.holdId==="string"&&typeof b.reason==="string"&&b.reason.trim().length>=5){fn="mme_warranty_api_security_evidence_release_hold";args={p_hold_id:b.holdId,p_actor_id:user.id,p_reason:b.reason};}
 else return out(400,"invalid_legal_hold_action",id);
 const result=await fetch(url+"/rest/v1/rpc/"+fn,{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify(args),cache:"no-store"}).catch(()=>null);
 if(!result?.ok)return out(409,"legal_hold_action_failed",id);
 return NextResponse.json({ok:true,requestId:id,result:await result.json().catch(()=>null)},{headers:{"Cache-Control":"no-store","X-Request-ID":id}});
}
