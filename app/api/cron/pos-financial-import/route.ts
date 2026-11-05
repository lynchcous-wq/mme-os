import { NextResponse } from "next/server";
import { authenticatePosRequest, isUuid } from "@/lib/pos/authenticated-server";

export const dynamic="force-dynamic";
export const revalidate=0;
const headers={"Cache-Control":"no-store, private"};
async function rpc(baseUrl:string,key:string,name:string,args:Record<string,unknown>){
 const r=await fetch(`${baseUrl}/rest/v1/rpc/${name}`,{method:"POST",headers:{apikey:key,Authorization:`Bearer ${key}`,"Content-Type":"application/json"},body:JSON.stringify(args),cache:"no-store"});
 if(!r.ok)throw new Error(`Worker operation ${name} failed.`);
 return r.json() as Promise<unknown>;
}
export async function POST(request:Request){
 const expected=process.env.CRON_SECRET;
 const workerPersonId=process.env.MME_FINANCIAL_WORKER_PERSON_ID;
 if(!expected||!isUuid(workerPersonId))return NextResponse.json({error:"Financial worker is not configured."},{status:503,headers});
 const supplied=request.headers.get("authorization")||"";
 if(supplied!==`Bearer ${expected}`)return NextResponse.json({error:"Unauthorized worker invocation."},{status:401,headers});
 const auth=await authenticatePosRequest(new Request(request.url,{headers:{Authorization:`Bearer ${process.env.MME_FINANCIAL_WORKER_SESSION_TOKEN||""}`}}));
 // A dedicated non-interactive worker identity must still have a valid Supabase session.
 if(!auth.ok)return NextResponse.json({error:"Configured worker session is unavailable."},{status:503,headers});
 if(auth.context.personId!==workerPersonId)return NextResponse.json({error:"Worker identity does not match configured service identity."},{status:403,headers});
 const {baseUrl,serviceKey}=auth.context;
 let enqueued=0,processed=0,retried=0,deadLettered=0;
 try{
  enqueued=Number(await rpc(baseUrl,serviceKey,"mme_pos_enqueue_financial_import_jobs",{p_actor_person_id:workerPersonId,p_limit:100}));
  for(let i=0;i<10;i++){
   const claimed=await rpc(baseUrl,serviceKey,"mme_pos_claim_financial_import_job",{p_worker_person_id:workerPersonId,p_lease_seconds:180}) as null|{job_id:string;batch_id:string;lease_token:string;attempt:number};
   if(!claimed)break;
   try{
    const result=await rpc(baseUrl,serviceKey,"mme_pos_process_financial_import_batch",{p_batch_id:claimed.batch_id,p_actor_person_id:workerPersonId});
    const status=await rpc(baseUrl,serviceKey,"mme_pos_finish_financial_import_job",{p_job_id:claimed.job_id,p_lease_token:claimed.lease_token,p_worker_person_id:workerPersonId,p_success:true,p_error_code:null,p_safe_error:null});
    if(status==="completed"||status==="completed_with_quarantine")processed++;
    else retried++;
   }catch{
    try{
     const status=await rpc(baseUrl,serviceKey,"mme_pos_finish_financial_import_job",{p_job_id:claimed.job_id,p_lease_token:claimed.lease_token,p_worker_person_id:workerPersonId,p_success:false,p_error_code:"IMPORT_WORKER_FAILURE",p_safe_error:"Import attempt failed; inspect restricted operational diagnostics."});
     if(status==="dead_letter")deadLettered++;else retried++;
    }catch{/* Lease expiry enables safe recovery if finalization itself fails. */}
   }
  }
  return NextResponse.json({ok:true,enqueued,processed,retried,dead_lettered:deadLettered},{headers});
 }catch{return NextResponse.json({error:"Financial import worker failed; no success is being reported."},{status:503,headers});}
}
