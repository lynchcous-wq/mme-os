import {NextRequest,NextResponse} from "next/server";
import {timingSafeEqual} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
function authorized(req:NextRequest){const expected=process.env.MME_EVIDENCE_RETENTION_WORKER_SECRET??"",given=(req.headers.get("authorization")??"").replace(/^Bearer\s+/i,"");if(!expected||!given)return false;const a=Buffer.from(expected),b=Buffer.from(given);return a.length===b.length&&timingSafeEqual(a,b);}
export async function POST(req:NextRequest){
 if(!authorized(req))return NextResponse.json({error:"unauthorized"},{status:401});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!url||!key)return NextResponse.json({error:"worker_not_configured"},{status:503});
 const claim=await fetch(url+"/rest/v1/rpc/mme_warranty_api_security_evidence_claim_retention_jobs",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify({p_batch_size:25}),cache:"no-store"}).catch(()=>null);
 if(!claim?.ok)return NextResponse.json({error:"retention_claim_failed"},{status:502});
 const jobs=await claim.json().catch(()=>null);if(!Array.isArray(jobs))return NextResponse.json({error:"invalid_retention_queue"},{status:502});
 let deleted=0,failed=0;
 for(const job of jobs){
  try{
   const hold=await fetch(url+"/rest/v1/mme_warranty_api_security_evidence_legal_holds?select=hold_id&evidence_id=eq."+encodeURIComponent(job.evidence_id)+"&released_at=is.null",{headers:{apikey:key,Authorization:"Bearer "+key},cache:"no-store"});
   if(!hold.ok)throw new Error("legal_hold_check_failed");const holds=await hold.json();if(holds.length){await fetch(url+"/rest/v1/rpc/mme_warranty_api_security_evidence_finish_retention",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify({p_job_id:job.job_id,p_deleted:false,p_error:"legal_hold_active"}),cache:"no-store"});continue;}
   const remove=await fetch(url+"/storage/v1/object/"+encodeURIComponent(job.storage_bucket)+"/"+job.storage_path.split("/").map(encodeURIComponent).join("/"),{method:"DELETE",headers:{apikey:key,Authorization:"Bearer "+key},cache:"no-store"});
   if(!remove.ok)throw new Error("storage_delete_failed");
   const finish=await fetch(url+"/rest/v1/rpc/mme_warranty_api_security_evidence_finish_retention",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify({p_job_id:job.job_id,p_deleted:true,p_error:null}),cache:"no-store"});if(!finish.ok)throw new Error("retention_finalize_failed");deleted++;
  }catch(e){failed++;await fetch(url+"/rest/v1/rpc/mme_warranty_api_security_evidence_finish_retention",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify({p_job_id:job.job_id,p_deleted:false,p_error:e instanceof Error?e.message:"retention_failed"}),cache:"no-store"}).catch(()=>null);}
 }
 return NextResponse.json({ok:true,claimed:jobs.length,deleted,failed},{headers:{"Cache-Control":"no-store"}});
}
