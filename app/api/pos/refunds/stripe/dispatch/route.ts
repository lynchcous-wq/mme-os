import {createHmac,timingSafeEqual} from "node:crypto";
import {NextResponse} from "next/server";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export const revalidate=0;
const headers={"Cache-Control":"no-store, private"};
type Claim={refund_request_id:string;tender_attempt_id:string;amount_minor:number;currency:string;provider_account_reference:string;provider_payment_reference:string;idempotency_key:string;lease_token:string};
function equalSecret(a:string,b:string){const x=Buffer.from(a),y=Buffer.from(b);return x.length===y.length&&timingSafeEqual(x,y);}
async function rpc(base:string,key:string,name:string,body:unknown){
 const response=await fetch(base+"/rest/v1/rpc/"+name,{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify(body),cache:"no-store"});
 if(!response.ok)throw new Error("trusted_rpc_failed_"+name);
 return response.json();
}
export async function POST(request:Request){
 const workerSecret=process.env.MME_POS_REFUND_WORKER_SECRET;
 const stripeSecret=process.env.STRIPE_SECRET_KEY;
 const base=process.env.SUPABASE_URL??process.env.NEXT_PUBLIC_SUPABASE_URL;
 const service=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!workerSecret||!stripeSecret||!base||!service)return NextResponse.json({error:"Stripe refund worker is not configured."},{status:503,headers});
 const supplied=request.headers.get("authorization")?.replace(/^Bearer\s+/i,"")??"";
 if(!equalSecret(supplied,workerSecret))return NextResponse.json({error:"Unauthorized."},{status:401,headers});
 let body:{limit?:number}={};try{body=await request.json();}catch{return NextResponse.json({error:"Invalid JSON."},{status:400,headers});}
 const limit=Number.isInteger(body.limit)?Math.min(10,Math.max(1,body.limit!)):5;
 let claims:Claim[];
 try{claims=await rpc(base,service,"mme_pos_claim_stripe_refund_dispatch",{p_limit:limit,p_lease_seconds:90}) as Claim[];}
 catch{return NextResponse.json({error:"Could not claim Stripe refund work."},{status:503,headers});}
 const results=[];
 for(const claim of claims){
  if(!claim.provider_payment_reference||!claim.provider_account_reference||!claim.idempotency_key||!claim.lease_token){
   try{await rpc(base,service,"mme_pos_finish_refund_dispatch",{p_refund_request_id:claim.refund_request_id,p_lease_token:claim.lease_token,p_outcome:"failed",p_failure_code:"stripe_claim_missing_reference"});}catch{}
   results.push({refund_request_id:claim.refund_request_id,status:"failed_validation"});continue;
  }
  try{
   const form=new URLSearchParams({
    payment_intent:claim.provider_payment_reference,
    amount:String(claim.amount_minor),
    "metadata[mme_refund_request_id]":claim.refund_request_id,
    "metadata[mme_tender_attempt_id]":claim.tender_attempt_id
   });
   const response=await fetch("https://api.stripe.com/v1/refunds",{
    method:"POST",headers:{Authorization:"Bearer "+stripeSecret,"Content-Type":"application/x-www-form-urlencoded",
     "Idempotency-Key":claim.idempotency_key,"Stripe-Account":claim.provider_account_reference},
    body:form.toString(),cache:"no-store",signal:AbortSignal.timeout(20000)
   });
   const result=await response.json() as Record<string,unknown>;
   if(!response.ok){
    const errorCode=typeof (result.error as Record<string,unknown>|undefined)?.code==="string"?String((result.error as Record<string,unknown>).code):"stripe_api_rejected";
    await rpc(base,service,"mme_pos_finish_refund_dispatch",{p_refund_request_id:claim.refund_request_id,p_lease_token:claim.lease_token,p_outcome:"failed",p_failure_code:errorCode});
    results.push({refund_request_id:claim.refund_request_id,status:"failed"});continue;
   }
   const refundId=typeof result.id==="string"?result.id:"";
   const status=typeof result.status==="string"?result.status:"";
   if(!refundId){await rpc(base,service,"mme_pos_finish_refund_dispatch",{p_refund_request_id:claim.refund_request_id,p_lease_token:claim.lease_token,p_outcome:"unknown_reconciliation"});results.push({refund_request_id:claim.refund_request_id,status:"unknown"});continue;}
   if(status==="succeeded"){
    await rpc(base,service,"mme_pos_finish_refund_dispatch",{p_refund_request_id:claim.refund_request_id,p_lease_token:claim.lease_token,p_outcome:"succeeded",p_provider_operation_reference:refundId,p_provider_refund_reference:refundId});
    results.push({refund_request_id:claim.refund_request_id,status:"completed"});
   }else{
    await rpc(base,service,"mme_pos_finish_refund_dispatch",{p_refund_request_id:claim.refund_request_id,p_lease_token:claim.lease_token,p_outcome:"unknown_reconciliation"});
    results.push({refund_request_id:claim.refund_request_id,status:"pending_reconciliation"});
   }
  }catch{
   try{await rpc(base,service,"mme_pos_finish_refund_dispatch",{p_refund_request_id:claim.refund_request_id,p_lease_token:claim.lease_token,p_outcome:"unknown_reconciliation"});}catch{}
   results.push({refund_request_id:claim.refund_request_id,status:"unknown_reconciliation"});
  }
 }
 return NextResponse.json({processed:results.length,results},{status:200,headers});
}
