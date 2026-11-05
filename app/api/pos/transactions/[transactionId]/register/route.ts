import {NextResponse} from "next/server";
import {authenticatePosRequest,isUuid} from "@/lib/pos/authenticated-server";
export const dynamic="force-dynamic";
export const revalidate=0;
export async function POST(request:Request,{params}:{params:Promise<{transactionId:string}>}){
 const auth=await authenticatePosRequest(request);
 if(!auth.ok)return auth.response;
 const {transactionId}=await params;
 if(!isUuid(transactionId))return NextResponse.json({error:"A valid transaction ID is required."},{status:400});
 let body:unknown;try{body=await request.json();}catch{return NextResponse.json({error:"Valid JSON is required."},{status:400});}
 if(!body||typeof body!=="object"||Array.isArray(body)||Object.keys(body).length!==1||typeof (body as Record<string,unknown>).register_reference!=="string")
  return NextResponse.json({error:"Provide only a register_reference."},{status:400});
 const register=(body as {register_reference:string}).register_reference;
 if(!/^[A-Za-z0-9][A-Za-z0-9._-]{1,119}$/.test(register))
  return NextResponse.json({error:"Register reference is invalid."},{status:400});
 try{
  const response=await fetch(auth.context.baseUrl+"/rest/v1/rpc/mme_pos_set_transaction_register",{
   method:"POST",headers:{apikey:auth.context.serviceKey,Authorization:"Bearer "+auth.context.serviceKey,"Content-Type":"application/json"},
   body:JSON.stringify({p_transaction_id:transactionId,p_actor_person_id:auth.context.personId,p_register_reference:register}),cache:"no-store"});
  if(!response.ok)return NextResponse.json({error:"Register could not be assigned to this POS transaction."},{status:response.status===403?403:409});
  return NextResponse.json({assigned:true},{headers:{"Cache-Control":"no-store"}});
 }catch{return NextResponse.json({error:"POS register assignment service is unavailable."},{status:503});}
}
