import { NextResponse } from "next/server";
import { authenticatePosRequest, isUuid } from "@/lib/pos/authenticated-server";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const headers = { "Cache-Control": "no-store, private" };

async function authorize(context: {baseUrl:string;serviceKey:string;personId:string}, permission:string, locationId:string) {
 const r=await fetch(`${context.baseUrl}/rest/v1/rpc/mme_pos_authorize_hardware_action`,{
  method:"POST",headers:{apikey:context.serviceKey,Authorization:`Bearer ${context.serviceKey}`,"Content-Type":"application/json"},
  body:JSON.stringify({p_actor_person_id:context.personId,p_permission_key:permission,p_location_id:locationId}),cache:"no-store"});
 return r.ok && await r.json()===true;
}
async function rpc(context:{baseUrl:string;serviceKey:string},name:string,args:Record<string,unknown>) {
 const r=await fetch(`${context.baseUrl}/rest/v1/rpc/${name}`,{
  method:"POST",headers:{apikey:context.serviceKey,Authorization:`Bearer ${context.serviceKey}`,"Content-Type":"application/json"},
  body:JSON.stringify(args),cache:"no-store"});
 if(!r.ok) throw new Error(r.status===403?"Permission denied": "Financial import service unavailable");
 return r.json() as Promise<unknown>;
}
async function read(context:{baseUrl:string;serviceKey:string},path:string) {
 const r=await fetch(`${context.baseUrl}/rest/v1/${path}`,{
  headers:{apikey:context.serviceKey,Authorization:`Bearer ${context.serviceKey}`,Accept:"application/json"},cache:"no-store"});
 if(!r.ok) throw new Error("Financial connector data unavailable");
 return r.json() as Promise<Record<string,unknown>[]>;
}
export async function GET(request:Request) {
 const auth=await authenticatePosRequest(request);
 if(!auth.ok)return auth.response;
 const locationId=new URL(request.url).searchParams.get("location_id");
 if(!isUuid(locationId))return NextResponse.json({error:"A valid store UUID is required."},{status:400,headers});
 if(!await authorize(auth.context,"pos.finance.connector.view",locationId))
  return NextResponse.json({error:"Connector view permission denied."},{status:403,headers});
 try {
  const [connectors,batches,quarantine,jobs,webhookEvents,syncRuns]=await Promise.all([
   read(auth.context,`mme_pos_financial_connectors?select=id,location_id,provider_key,source_system,display_name,status,external_account_reference,adapter_version,last_success_at,last_attempt_at,last_error_code,created_at&location_id=eq.${locationId}&order=created_at.desc`),
   read(auth.context,`mme_pos_financial_import_batches?select=id,connector_id,source_batch_reference,status,record_count,imported_count,duplicate_count,quarantined_count,staged_at,completed_at&location_id=eq.${locationId}&order=staged_at.desc&limit=100`),
   read(auth.context,`mme_pos_financial_import_quarantine?select=id,batch_id,import_row_id,error_code,safe_message,resolution_status,created_at&location_id=eq.${locationId}&resolution_status=eq.open&order=created_at.desc&limit=100`),
   read(auth.context,`mme_pos_financial_import_jobs?select=id,batch_id,connector_id,status,attempts,max_attempts,available_at,lease_expires_at,last_error_code,created_at,updated_at&location_id=eq.${locationId}&order=created_at.desc&limit=100`),
   read(auth.context,`mme_pos_financial_webhook_events?select=id,provider_event_id,provider_event_type,status,received_at,processed_at,safe_error_code&location_id=eq.${locationId}&order=received_at.desc&limit=100`),
   read(auth.context,`mme_pos_financial_sync_runs?select=id,connector_id,provider_key,status,records_fetched,records_staged,records_ignored,batches_staged,safe_error_code,started_at,finished_at&location_id=eq.${locationId}&order=started_at.desc&limit=100`)
  ]);
  return NextResponse.json({connectors,batches,open_quarantine:quarantine,jobs,webhook_events:webhookEvents,sync_runs:syncRuns},{headers});
 } catch {return NextResponse.json({error:"Unable to load financial connector status."},{status:503,headers});}
}
export async function POST(request:Request) {
 const auth=await authenticatePosRequest(request);
 if(!auth.ok)return auth.response;
 let body:unknown;try{body=await request.json();}catch{return NextResponse.json({error:"Valid JSON is required."},{status:400,headers});}
 if(!body||typeof body!=="object"||Array.isArray(body))return NextResponse.json({error:"Invalid connector request."},{status:400,headers});
 const b=body as Record<string,unknown>;
 const allowed=["action","location_id","provider_key","display_name","external_account_reference","credential_reference","connector_id","source_batch_reference","idempotency_key","records","source_digest_sha256","batch_id","next_status","reason"];
 if(Object.keys(b).some(k=>!allowed.includes(k)))return NextResponse.json({error:"Unsupported request fields."},{status:400,headers});
 if(!isUuid(b.location_id)||typeof b.action!=="string")return NextResponse.json({error:"A valid store and action are required."},{status:400,headers});
 if(b.action==="register_connector") {
  if(!await authorize(auth.context,"pos.finance.connector.manage",b.location_id))return NextResponse.json({error:"Connector management permission denied."},{status:403,headers});
  if(typeof b.provider_key!=="string"||typeof b.display_name!=="string"||
   (b.external_account_reference!==undefined&&typeof b.external_account_reference!=="string")||
   (b.credential_reference!==undefined&&typeof b.credential_reference!=="string"))
   return NextResponse.json({error:"Invalid connector metadata."},{status:400,headers});
  try {const id=await rpc(auth.context,"mme_pos_register_financial_connector",{p_location_id:b.location_id,p_actor_person_id:auth.context.personId,p_provider_key:b.provider_key,p_display_name:b.display_name,p_external_account_reference:b.external_account_reference??null,p_credential_reference:b.credential_reference??null});return NextResponse.json({connector_id:id},{status:201,headers});}
  catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Connector registration failed."},{status:503,headers});}
 }
 if(b.action==="set_connector_status") {
  if(!isUuid(b.connector_id)||typeof b.next_status!=="string"||typeof b.reason!=="string"||b.reason.trim().length<8)
   return NextResponse.json({error:"A connector, valid status and reason are required."},{status:400,headers});
  if(!await authorize(auth.context,"pos.finance.connector.manage",b.location_id))return NextResponse.json({error:"Connector management permission denied."},{status:403,headers});
  try {
   const connectors=await read(auth.context,`mme_pos_financial_connectors?select=id,location_id&id=eq.${b.connector_id}&limit=1`);
   if(!connectors.length||connectors[0].location_id!==b.location_id)return NextResponse.json({error:"Connector does not belong to the requested store."},{status:404,headers});
   await rpc(auth.context,"mme_pos_set_financial_connector_status",{p_connector_id:b.connector_id,p_actor_person_id:auth.context.personId,p_next_status:b.next_status,p_reason:b.reason});
   return NextResponse.json({updated:true},{headers});
  }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Connector status update failed."},{status:503,headers});}
 }
 if(b.action==="stage_batch") {
  if(!isUuid(b.connector_id)||typeof b.source_batch_reference!=="string"||typeof b.idempotency_key!=="string"||!Array.isArray(b.records)||b.records.length<1||b.records.length>250)
   return NextResponse.json({error:"A connector, batch reference, idempotency key and 1–250 normalized rows are required."},{status:400,headers});
  if(!await authorize(auth.context,"pos.finance.report.import",b.location_id))return NextResponse.json({error:"Financial import permission denied."},{status:403,headers});
  try {
   const connectors=await read(auth.context,`mme_pos_financial_connectors?select=id,location_id&id=eq.${b.connector_id}&limit=1`);
   if(!connectors.length||connectors[0].location_id!==b.location_id)return NextResponse.json({error:"Connector does not belong to the requested store."},{status:404,headers});
   const id=await rpc(auth.context,"mme_pos_stage_financial_import_batch",{p_connector_id:b.connector_id,p_actor_person_id:auth.context.personId,p_source_batch_reference:b.source_batch_reference,p_idempotency_key:b.idempotency_key,p_records:b.records,p_source_digest_sha256:b.source_digest_sha256??null});
   return NextResponse.json({batch_id:id},{status:201,headers});
  }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Batch staging failed."},{status:503,headers});}
 }
 if(b.action==="process_batch") {
  if(!isUuid(b.batch_id))return NextResponse.json({error:"A valid batch UUID is required."},{status:400,headers});
  if(!await authorize(auth.context,"pos.finance.report.import",b.location_id))return NextResponse.json({error:"Financial import permission denied."},{status:403,headers});
  try {
   const batches=await read(auth.context,`mme_pos_financial_import_batches?select=id,location_id&id=eq.${b.batch_id}&limit=1`);
   if(!batches.length||batches[0].location_id!==b.location_id)return NextResponse.json({error:"Batch does not belong to the requested store."},{status:404,headers});
   const result=await rpc(auth.context,"mme_pos_process_financial_import_batch",{p_batch_id:b.batch_id,p_actor_person_id:auth.context.personId});
   return NextResponse.json({result},{headers});
  }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Batch processing failed."},{status:503,headers});}
 }
 return NextResponse.json({error:"Unsupported connector action."},{status:400,headers});
}
