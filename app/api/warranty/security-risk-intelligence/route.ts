import {NextRequest,NextResponse} from "next/server";
import {randomUUID} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
const roles=["ceo","privacy_officer","manager","warranty_specialist"] as const;
type Role=typeof roles[number];
const send=(status:number,error:string,id:string)=>NextResponse.json({error,requestId:id},{status,headers:{"Cache-Control":"no-store","X-Request-ID":id}});
async function session(req:NextRequest){const url=process.env.NEXT_PUBLIC_SUPABASE_URL,anon=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,key=process.env.SUPABASE_SERVICE_ROLE_KEY,token=(req.headers.get("authorization")??"").match(/^Bearer\s+(.+)$/i)?.[1];if(!url||!anon||!key||!token)return null;const res=await fetch(url+"/auth/v1/user",{headers:{apikey:anon,Authorization:"Bearer "+token},cache:"no-store"}).catch(()=>null);if(!res?.ok)return null;const user=await res.json().catch(()=>null),raw=user?.app_metadata?.roles??(user?.app_metadata?.role?[user.app_metadata.role]:[]),userRoles=Array.isArray(raw)?raw.filter((r:unknown):r is Role=>typeof r==="string"&&roles.includes(r as Role)):[];return user?.id?{url,key,user,roles:userRoles}:null;}
export async function GET(req:NextRequest){
 const id=randomUUID(),a=await session(req);if(!a)return send(401,"authentication_required",id);
 if(!a.roles.some(r=>roles.includes(r)))return send(403,"risk_intelligence_access_denied",id);
 const limit=Math.max(1,Math.min(200,Number(req.nextUrl.searchParams.get("limit")??50)||50));
 const q=await fetch(a.url+"/rest/v1/mme_warranty_security_case_risk_intelligence?select=*&order=risk_score.desc&limit="+limit,{headers:{apikey:a.key,Authorization:"Bearer "+a.key},cache:"no-store"}).catch(()=>null);
 if(!q?.ok)return send(502,"risk_intelligence_unavailable",id);
 return NextResponse.json({requestId:id,data:await q.json(),limit,asOf:new Date().toISOString()},{headers:{"Cache-Control":"no-store","X-Request-ID":id}});
}
export async function POST(req:NextRequest){
 const id=randomUUID(),a=await session(req);if(!a)return send(401,"authentication_required",id);
 if(!a.roles.some(r=>r==="ceo"||r==="privacy_officer"||r==="manager"))return send(403,"risk_review_permission_required",id);
 let body:any;try{body=await req.json();}catch{return send(400,"invalid_json",id);}
 if(!body||typeof body.signalId!=="string"||! /^[0-9a-f-]{36}$/i.test(body.signalId)||!["accepted","dismissed","needs_context"].includes(body.status)||typeof body.note!=="string"||body.note.trim().length<5||body.note.trim().length>2000)return send(400,"invalid_review",id);
 const result=await fetch(a.url+"/rest/v1/rpc/mme_warranty_api_security_risk_review",{method:"POST",headers:{apikey:a.key,Authorization:"Bearer "+a.key,"Content-Type":"application/json"},body:JSON.stringify({p_signal_id:body.signalId,p_reviewer_id:a.user.id,p_status:body.status,p_note:body.note.trim(),p_request_id:id}),cache:"no-store"}).catch(()=>null);
 if(!result?.ok)return send(409,"risk_review_failed",id);
 return NextResponse.json({ok:true,requestId:id},{headers:{"Cache-Control":"no-store","X-Request-ID":id}});
}
