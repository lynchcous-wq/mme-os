import {createHash} from "node:crypto";
import {NextResponse} from "next/server";
import {fetchStripeBalanceTransactions,normalizeStripeBalanceTransactions} from "@/lib/pos/financial-adapters/stripe-balance-transactions";
export const dynamic="force-dynamic";
export const revalidate=0;
const headers={"Cache-Control":"no-store, private"};
type Connector={id:string;location_id:string;provider_key:string;source_system:string;external_account_reference:string|null;credential_reference:string|null;status:string};
type Cursor={created_gte:number;starting_after:string|null;high_water_created:number};
async function rpc(baseUrl:string,key:string,name:string,args:Record<string,unknown>){
 const response=await fetch(baseUrl+"/rest/v1/rpc/"+name,{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify(args),cache:"no-store"});
 if(!response.ok)throw new Error("FINANCIAL_SYNC_DATABASE_OPERATION_FAILED");
 return response.json() as Promise<unknown>;
}
async function rows(baseUrl:string,key:string,path:string){
 const response=await fetch(baseUrl+"/rest/v1/"+path,{headers:{apikey:key,Authorization:"Bearer "+key,Accept:"application/json"},cache:"no-store"});
 if(!response.ok)throw new Error("FINANCIAL_SYNC_DATABASE_READ_FAILED");
 return response.json() as Promise<Record<string,unknown>[]>;
}
function parseCursor(value:unknown,now:number):Cursor{
 if(typeof value!=="string")return {created_gte:now-3*86400,starting_after:null,high_water_created:now};
 try{const v=JSON.parse(value) as Partial<Cursor>;if(Number.isInteger(v.created_gte)&&typeof v.high_water_created==="number")return {created_gte:v.created_gte!,starting_after:typeof v.starting_after==="string"?v.starting_after:null,high_water_created:v.high_water_created};}catch{}
 return {created_gte:now-3*86400,starting_after:null,high_water_created:now};
}
async function syncStripe(baseUrl:string,key:string,workerId:string,connector:Connector,timezone:string){
 const cursorRows=await rows(baseUrl,key,"mme_pos_financial_import_cursors?select=cursor_value&connector_id=eq."+connector.id+"&limit=1");
 const now=Math.floor(Date.now()/1000),cursor=parseCursor(cursorRows[0]?.cursor_value,now);
 const runId=await rpc(baseUrl,key,"mme_pos_start_financial_sync_run",{p_connector_id:connector.id,p_worker_person_id:workerId,p_window_started_at:new Date(cursor.created_gte*1000).toISOString()});
 if(typeof runId!=="string")return {connector_id:connector.id,status:"already_running"};
 let startingAfter=cursor.starting_after,highWater=cursor.high_water_created;
 let fetched=0,staged=0,ignored=0,batches=0,hasMore=false;
 const maxPages=3;
 try{
  const secretName=connector.credential_reference||"STRIPE_SECRET_KEY";
  if(!/^[A-Z][A-Z0-9_]{2,80}$/.test(secretName)||!process.env[secretName])throw new Error("STRIPE_CREDENTIAL_NOT_CONFIGURED");
  if(connector.external_account_reference&&!/^acct_[A-Za-z0-9]+$/.test(connector.external_account_reference))throw new Error("STRIPE_ACCOUNT_REFERENCE_INVALID");
  for(let pageNo=0;pageNo<maxPages;pageNo++){
   const page=await fetchStripeBalanceTransactions({secretKey:process.env[secretName]!,accountId:connector.external_account_reference||undefined,createdGte:cursor.created_gte,startingAfter});
   fetched+=page.data.length;
   if(!startingAfter&&page.data.length)highWater=page.data[0].created;
   const normalized=normalizeStripeBalanceTransactions({data:page.data,timezone});
   ignored+=normalized.ignored;
   if(normalized.records.length){
    const first=page.data[0]?.id||"empty",last=page.data[page.data.length-1]?.id||"empty";
    const batchRef="stripe-balance-"+first+"-"+last;
    const idempotency="stripe-page-"+createHash("sha256").update(connector.id+":"+cursor.created_gte+":"+first+":"+last).digest("hex");
    const pageDigest=createHash("sha256").update(JSON.stringify(page.data)).digest("hex");
    await rpc(baseUrl,key,"mme_pos_stage_financial_import_batch",{p_connector_id:connector.id,p_actor_person_id:workerId,p_source_batch_reference:batchRef,p_idempotency_key:idempotency,p_records:normalized.records,p_source_digest_sha256:pageDigest});
    staged+=normalized.records.length;batches++;
   }
   hasMore=page.has_more;
   if(!hasMore){startingAfter=null;break;}
   if(!page.data.length)throw new Error("STRIPE_PAGINATION_STALLED");
   startingAfter=page.data[page.data.length-1].id;
  }
  const nextCursor:Cursor=hasMore
   ? {created_gte:cursor.created_gte,starting_after:startingAfter,high_water_created:highWater}
   : {created_gte:Math.max(now-600,highWater-600),starting_after:null,high_water_created:Math.max(now,highWater)};
  const nextValue=JSON.stringify(nextCursor);
  await rpc(baseUrl,key,"mme_pos_finish_financial_sync_run",{p_run_id:runId,p_worker_person_id:workerId,p_status:hasMore?"partial":"completed",p_cursor_value:nextValue,p_records_fetched:fetched,p_records_staged:staged,p_records_ignored:ignored,p_batches_staged:batches,p_safe_error_code:null});
  return {connector_id:connector.id,status:hasMore?"partial":"completed",records_fetched:fetched,records_staged:staged,records_ignored:ignored,batches_staged:batches};
 }catch(error){
  await rpc(baseUrl,key,"mme_pos_finish_financial_sync_run",{p_run_id:runId,p_worker_person_id:workerId,p_status:"failed",p_cursor_value:JSON.stringify(cursor),p_records_fetched:fetched,p_records_staged:staged,p_records_ignored:ignored,p_batches_staged:batches,p_safe_error_code:error instanceof Error&&error.message==="STRIPE_CREDENTIAL_NOT_CONFIGURED"?"CREDENTIAL_NOT_CONFIGURED":error instanceof Error&&error.message==="STRIPE_ACCOUNT_REFERENCE_INVALID"?"ACCOUNT_REFERENCE_INVALID":"PROVIDER_SYNC_FAILED"});
  throw error;
 }
}
export async function POST(request:Request){
 const cronSecret=process.env.CRON_SECRET,workerId=process.env.MME_FINANCIAL_WORKER_PERSON_ID;
 const baseUrl=process.env.SUPABASE_URL??process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!cronSecret||!workerId||!baseUrl||!key)return NextResponse.json({error:"Provider sync is not configured."},{status:503,headers});
 if(request.headers.get("authorization")!=="Bearer "+cronSecret)return NextResponse.json({error:"Unauthorized."},{status:401,headers});
 try{
  const authorized=await rpc(baseUrl,key,"mme_pos_authorize_financial_worker",{p_worker_person_id:workerId});
  if(authorized!==true)return NextResponse.json({error:"Worker identity is not authorized."},{status:403,headers});
  const connectors=await rows(baseUrl,key,"mme_pos_financial_connectors?select=id,location_id,provider_key,source_system,external_account_reference,credential_reference,status&status=eq.active&provider_key=eq.stripe&order=created_at.asc&limit=25") as unknown as Connector[];
  const timezone=process.env.MME_FINANCIAL_BUSINESS_TIMEZONE||"America/New_York";
  try{new Intl.DateTimeFormat("en-US",{timeZone:timezone});}catch{return NextResponse.json({error:"Business timezone is invalid."},{status:503,headers});}
  const results=[] as Record<string,unknown>[];
  for(const connector of connectors){try{results.push(await syncStripe(baseUrl,key,workerId,connector,timezone));}catch{results.push({connector_id:connector.id,status:"failed",error:"PROVIDER_SYNC_FAILED"});}}
  return NextResponse.json({ok:true,provider:"stripe_balance_transactions",connectors_checked:connectors.length,results},{headers});
 }catch{return NextResponse.json({error:"Provider synchronization failed."},{status:503,headers});}
}
export async function GET(request:Request){return POST(request);}
