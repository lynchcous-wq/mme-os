import{NextResponse}from"next/server";import{randomUUID}from"node:crypto";import{dispatch,type Job,type Channel}from"@/lib/security-notification-channel-adapters";
export const runtime="nodejs";export const dynamic="force-dynamic";export const revalidate=0;
const headers={"Cache-Control":"no-store, private"};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
async function rpc(base:string,key:string,name:string,args:Record<string,unknown>){const r=await fetch(base+"/rest/v1/rpc/"+name,{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify(args),cache:"no-store"});if(!r.ok)throw new Error("WORKER_RPC_FAILED:"+name);return r.json() as Promise<any>;}
export async function POST(request:Request){const id=randomUUID(),secret=process.env.CRON_SECRET,worker=process.env.MME_NOTIFICATION_ESCALATION_WORKER_ID,base=process.env.SUPABASE_URL??process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
if(!secret||!worker||!uuid.test(worker)||!base||!key)return NextResponse.json({error:"escalation_worker_not_configured",requestId:id},{status:503,headers});
if(request.headers.get("authorization")!=="Bearer "+secret)return NextResponse.json({error:"unauthorized_worker_invocation",requestId:id},{status:401,headers});
const channels=(process.env.MME_ESCALATION_DISPATCH_CHANNELS??"").split(",").map(x=>x.trim()).filter((x):x is Channel=>["email","sms","pager","push"].includes(x));
if(!channels.length)return NextResponse.json({error:"escalation_channels_not_configured",requestId:id},{status:503,headers});
try{
const overdue=await rpc(base,key,"mme_security_notification_claim_acknowledgement_sla",{p_worker:worker,p_limit:50});
const materialized=await rpc(base,key,"mme_security_notification_materialize_escalation_dispatch",{});
const channelJobs=await rpc(base,key,"mme_security_notification_materialize_escalation_channels",{p_channels:channels});
const claimed=await rpc(base,key,"mme_security_notification_claim_escalation_channels",{p_worker:worker,p_limit:40}) as {channel_delivery_id:string;dispatch_id:string;alert_id:string;target_role:string;channel:Channel;attempt_count:number;title:string;summary:string;severity:string;escalation_level:number}[];
let accepted=0,failed=0,skipped=0;
for(const item of claimed??[]){const job:Job={delivery_id:item.channel_delivery_id,alert_id:item.alert_id,channel:item.channel,recipient_role:item.target_role,attempt_count:item.attempt_count,max_attempts:5,title:"Escalation L"+item.escalation_level+": "+item.title,message:item.summary,severity:item.severity};const result=await dispatch(job);await rpc(base,key,"mme_security_notification_finish_escalation_channel",{p_channel_delivery:item.channel_delivery_id,p_worker:worker,p_provider:result.provider,p_outcome:result.outcome,p_reference:result.reference??null,p_error:result.error??null,p_request:id});if(result.outcome==="accepted"||result.outcome==="delivered")accepted++;else if(result.outcome==="skipped")skipped++;else failed++;}
return NextResponse.json({ok:true,requestId:id,overdue_alerts:Array.isArray(overdue)?overdue.length:0,dispatch_jobs_materialized:Number(materialized)||0,channel_jobs_materialized:Number(channelJobs)||0,channel_jobs_claimed:claimed?.length??0,channels_accepted:accepted,channels_failed:failed,channels_skipped:skipped},{headers});
}catch{return NextResponse.json({error:"escalation_worker_failed",requestId:id},{status:503,headers});}}
export async function GET(request:Request){return POST(request);}
