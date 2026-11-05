import { NextResponse } from "next/server";
export const dynamic="force-dynamic";
export const revalidate=0;
const headers={"Cache-Control":"no-store, private"};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
async function rpc(baseUrl:string,key:string,name:string,args:Record<string,unknown>){
 const r=await fetch(`${baseUrl}/rest/v1/rpc/${name}`,{method:"POST",headers:{apikey:key,Authorization:`Bearer ${key}`,"Content-Type":"application/json"},body:JSON.stringify(args),cache:"no-store"});
 if(!r.ok)throw new Error(`Worker operation ${name} failed.`);
 return r.json() as Promise<unknown>;
}
export async function POST(request:Request){
 const expected=process.env.CRON_SECRET,workerPersonId=process.env.MME_FINANCIAL_WORKER_PERSON_ID;
 const baseUrl=process.env.SUPABASE_URL??process.env.NEXT_PUBLIC_SUPABASE_URL;
 const serviceKey=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!expected||!workerPersonId||!uuid.test(workerPersonId)||!baseUrl||!serviceKey)
  return NextResponse.json({error:"Financial worker is not configured."},{status:503,headers});
 if(request.headers.get("authorization")!==`Bearer ${expected}`)
  return NextResponse.json({error:"Unauthorized worker invocation."},{status:401,headers});
 try{
  const active=await rpc(baseUrl,serviceKey,"mme_pos_authorize_financial_worker",{p_worker_person_id:workerPersonId});
  if(active!==true)return NextResponse.json({error:"Configured worker identity is not authorized."},{status:403,headers});
  const expired=Number(await rpc(baseUrl,serviceKey,"mme_pos_expire_financial_import_jobs",{p_worker_person_id:workerPersonId}));
  let enqueued=Number(await rpc(baseUrl,serviceKey,"mme_pos_enqueue_financial_import_jobs",{p_actor_person_id:workerPersonId,p_limit:100}));
  let processed=0,retried=0,deadLettered=0;
  for(let i=0;i<10;i++){
   const claimed=await rpc(baseUrl,serviceKey,"mme_pos_claim_financial_import_job",{p_worker_person_id:workerPersonId,p_lease_seconds:180}) as null|{job_id:string;batch_id:string;lease_token:string};
   if(!claimed)break;
   try{
    await rpc(baseUrl,serviceKey,"mme_pos_process_financial_import_batch",{p_batch_id:claimed.batch_id,p_actor_person_id:workerPersonId});
    const status=await rpc(baseUrl,serviceKey,"mme_pos_finish_financial_import_job",{p_job_id:claimed.job_id,p_lease_token:claimed.lease_token,p_worker_person_id:workerPersonId,p_success:true,p_error_code:null,p_safe_error:null});
    if(status==="completed"||status==="completed_with_quarantine")processed++;else retried++;
   }catch{
    try{
     const status=await rpc(baseUrl,serviceKey,"mme_pos_finish_financial_import_job",{p_job_id:claimed.job_id,p_lease_token:claimed.lease_token,p_worker_person_id:workerPersonId,p_success:false,p_error_code:"IMPORT_WORKER_FAILURE",p_safe_error:"Import attempt failed; inspect restricted operational diagnostics."});
     if(status==="dead_letter")deadLettered++;else retried++;
    }catch{/* An expired lease is recovered by the next invocation. */}
   }
  }
  return NextResponse.json({ok:true,enqueued,processed,retried,dead_lettered:deadLettered,expired},{headers});
 }catch{return NextResponse.json({error:"Financial import worker failed; no success is being reported."},{status:503,headers});}
}

export async function GET(request:Request){return POST(request);}
