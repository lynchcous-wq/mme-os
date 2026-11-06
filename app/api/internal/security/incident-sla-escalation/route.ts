import {NextRequest,NextResponse} from "next/server";
import {randomUUID} from "node:crypto";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function POST(req:NextRequest){
 const requestId=randomUUID(),secret=process.env.MME_SECURITY_INCIDENT_WORKER_SECRET;
 const supplied=(req.headers.get("authorization")??"").match(/^Bearer\s+(.+)$/i)?.[1];
 if(!secret)return NextResponse.json({error:"worker_not_configured",requestId},{status:503});
 if(!supplied||supplied!==secret)return NextResponse.json({error:"worker_unauthorized",requestId},{status:401});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!url||!key)return NextResponse.json({error:"database_configuration_missing",requestId},{status:503});
 const r=await fetch(url+"/rest/v1/rpc/mme_security_incident_escalate_overdue_cases",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:"{}",cache:"no-store"}).catch(()=>null);
 if(!r?.ok)return NextResponse.json({error:"incident_escalation_worker_failed",requestId},{status:502});
 return NextResponse.json({requestId,result:await r.json()},{headers:{"Cache-Control":"no-store","X-Request-ID":requestId}});
}