import {NextResponse} from "next/server";
export const dynamic="force-dynamic";
export const revalidate=0;
const headers={"Cache-Control":"no-store, private"};
type Claim={transaction_id:string;location_id:string;business_timezone:string;lease_token:string};
async function rpc(baseUrl:string,key:string,name:string,args:Record<string,unknown>){
 const r=await fetch(baseUrl+"/rest/v1/rpc/"+name,{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify(args),cache:"no-store"});
 if(!r.ok)throw new Error("NATIVE_POS_FINANCIAL_EXPORT_RPC_FAILED");
 return r.json() as Promise<unknown>;
}
export async function POST(request:Request){
 const cronSecret=process.env.CRON_SECRET,workerId=process.env.MME_FINANCIAL_WORKER_PERSON_ID;
 const baseUrl=process.env.SUPABASE_URL??process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!cronSecret||!workerId||!baseUrl||!key)return NextResponse.json({error:"Native POS financial export is not configured."},{status:503,headers});
 if(request.headers.get("authorization")!=="Bearer "+cronSecret)return NextResponse.json({error:"Unauthorized."},{status:401,headers});
 try{
  const claims=await rpc(baseUrl,key,"mme_pos_claim_native_financial_exports",{p_worker_person_id:workerId,p_limit:25,p_lease_seconds:120}) as Claim[];
  if(!Array.isArray(claims))throw new Error("NATIVE_POS_FINANCIAL_CLAIM_INVALID");
  const results=[] as Array<Record<string,unknown>>;
  for(const claim of claims){
   try{
    const result=await rpc(baseUrl,key,"mme_pos_export_finalized_transaction_financial_facts",{
     p_transaction_id:claim.transaction_id,p_lease_token:claim.lease_token,p_worker_person_id:workerId,p_business_timezone:claim.business_timezone
    });
    results.push({transaction_id:claim.transaction_id,location_id:claim.location_id,status:result===true?"exported":"failed"});
   }catch{results.push({transaction_id:claim.transaction_id,location_id:claim.location_id,status:"failed",error:"EXPORT_RPC_FAILED"});}
  }
  return NextResponse.json({ok:true,claimed:claims.length,exported:results.filter(x=>x.status==="exported").length,results},{headers});
 }catch{return NextResponse.json({error:"Native POS financial export worker failed."},{status:503,headers});}
}
export async function GET(request:Request){return POST(request);}
