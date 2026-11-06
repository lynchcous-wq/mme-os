import {NextRequest,NextResponse} from "next/server";
import {timingSafeEqual,createHash} from "node:crypto";
export const runtime="nodejs";export const dynamic="force-dynamic";
function authorized(req:NextRequest){const expected=process.env.MME_EVIDENCE_SCAN_WORKER_SECRET??"",supplied=(req.headers.get("authorization")??"").replace(/^Bearer\s+/i,"");if(!expected||!supplied)return false;const a=Buffer.from(expected),b=Buffer.from(supplied);return a.length===b.length&&timingSafeEqual(a,b);}
async function finish(url:string,key:string,jobId:string,outcome:string,scanner:string,result:string,error:string|null){const r=await fetch(url+"/rest/v1/rpc/mme_warranty_api_security_evidence_finish_scan",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify({p_job_id:jobId,p_outcome:outcome,p_scanner_name:scanner,p_result_code:result,p_error_code:error}),cache:"no-store"});if(!r.ok)throw new Error("scan_result_persist_failed");}
export async function POST(req:NextRequest){
 if(!authorized(req))return NextResponse.json({error:"unauthorized"},{status:401});
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY,scannerUrl=process.env.MME_EVIDENCE_SCANNER_URL,scannerToken=process.env.MME_EVIDENCE_SCANNER_TOKEN;
 if(!url||!key)return NextResponse.json({error:"worker_not_configured"},{status:503});
 let jobs:any[];try{const r=await fetch(url+"/rest/v1/rpc/mme_warranty_api_security_evidence_claim_scan_jobs",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify({p_batch_size:20}),cache:"no-store"});if(!r.ok)throw new Error();jobs=await r.json();if(!Array.isArray(jobs))throw new Error();}catch{return NextResponse.json({error:"scan_queue_claim_failed"},{status:502});}
 let clean=0,quarantined=0,failed=0;
 for(const job of jobs){
  try{
   if(!scannerUrl||!scannerToken)throw new Error("scanner_not_configured");\n   const parsedScannerUrl=new URL(scannerUrl);if(parsedScannerUrl.protocol!=="https:")throw new Error("scanner_url_must_use_https");
   const object=await fetch(url+"/storage/v1/object/"+job.storage_bucket+"/"+job.storage_path,{headers:{apikey:key,Authorization:"Bearer "+key},cache:"no-store"});
   if(!object.ok)throw new Error("evidence_object_unavailable");
   const bytes=await object.arrayBuffer();
   if(bytes.byteLength!==Number(job.byte_size)||!job.sha256_hex)throw new Error("evidence_size_or_digest_metadata_missing");\n   const actualDigest=createHash("sha256").update(Buffer.from(bytes)).digest("hex");if(actualDigest!==job.sha256_hex)throw new Error("evidence_digest_mismatch");
   const scan=await fetch(scannerUrl,{method:"POST",headers:{Authorization:"Bearer "+scannerToken,"Content-Type":"application/octet-stream","X-Expected-SHA256":job.sha256_hex},body:bytes,cache:"no-store"});
   if(!scan.ok)throw new Error("scanner_unavailable");
   const result=await scan.json().catch(()=>null);
   if(!result||typeof result.clean!=="boolean")throw new Error("invalid_scanner_response");
   const outcome=result.clean?"clean":"quarantined";
   await finish(url,key,job.job_id,outcome,String(result.scanner??"external-scanner"),String(result.code??(result.clean?"clean":"threat_detected")),null);
   if(result.clean)clean++;else quarantined++;
  }catch(e){const code=e instanceof Error?e.message:"scan_failed";try{await finish(url,key,job.job_id,"failed","external-scanner","scan_error",code);}catch{}failed++;}
 }
 return NextResponse.json({ok:true,claimed:jobs.length,clean,quarantined,failed},{headers:{"Cache-Control":"no-store"}});
}
