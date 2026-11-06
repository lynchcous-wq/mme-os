import {NextRequest,NextResponse} from "next/server";
import {timingSafeEqual} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
function authorized(req:NextRequest){const expected=process.env.MME_SECURITY_NOTIFICATION_WORKER_SECRET??"";const supplied=(req.headers.get("authorization")??"").replace(/^Bearer\\s+/i,"");if(!expected||!supplied)return false;const a=Buffer.from(expected),b=Buffer.from(supplied);return a.length===b.length&&timingSafeEqual(a,b);}
export async function POST(req:NextRequest){
 if(!authorized(req))return NextResponse.json({error:"unauthorized"},{status:401});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)return NextResponse.json({error:"worker_not_configured"},{status:503});
 const r=await fetch(url+"/rest/v1/rpc/mme_warranty_api_enqueue_incident_notifications",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify({p_batch_size:100}),cache:"no-store"}).catch(()=>null);
 if(!r?.ok)return NextResponse.json({error:"notification_enqueue_failed"},{status:502});
 const queued=await r.json().catch(()=>0);
 return NextResponse.json({ok:true,queued},{headers:{"Cache-Control":"no-store"}});
}