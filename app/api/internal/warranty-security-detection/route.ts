import { NextRequest, NextResponse } from "next/server";
import { timingSafeEqual } from "node:crypto";
export const runtime="nodejs";
export const dynamic="force-dynamic";
function authorized(req:NextRequest){
 const expected=process.env.MME_SECURITY_WORKER_SECRET??"";
 const supplied=(req.headers.get("authorization")??"").replace(/^Bearer\\s+/i,"");
 if(!expected||!supplied)return false;
 const a=Buffer.from(expected),b=Buffer.from(supplied);
 return a.length===b.length&&timingSafeEqual(a,b);
}
export async function POST(req:NextRequest){
 if(!authorized(req))return NextResponse.json({error:"unauthorized"},{status:401,headers:{"Cache-Control":"no-store"}});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)return NextResponse.json({error:"worker_not_configured"},{status:503});
 const result=await fetch(url+"/rest/v1/rpc/mme_warranty_api_run_security_detection",{
  method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},
  body:JSON.stringify({p_batch_size:250}),cache:"no-store"
 }).catch(()=>null);
 if(!result?.ok)return NextResponse.json({error:"detection_run_failed"},{status:502});
 const data=await result.json().catch(()=>null);
 return NextResponse.json({ok:true,result:data},{headers:{"Cache-Control":"no-store"}});
}