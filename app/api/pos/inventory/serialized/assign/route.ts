import {NextResponse} from "next/server";
import {authenticatePosRequest,isUuid} from "@/lib/pos/authenticated-server";
export const dynamic="force-dynamic";
export const revalidate=0;
const headers={"Cache-Control":"no-store, private"};
export async function POST(request:Request){
 const auth=await authenticatePosRequest(request);
 if(!auth.ok)return auth.response;
 let body:unknown;try{body=await request.json();}catch{return NextResponse.json({error:"Valid JSON is required."},{status:400,headers});}
 if(!body||typeof body!=="object"||Array.isArray(body))return NextResponse.json({error:"Invalid serial assignment request."},{status:400,headers});
 const b=body as Record<string,unknown>;
 if(Object.keys(b).some(k=>!["order_line_id","serial_unit_id"].includes(k))||!isUuid(b.order_line_id)||!isUuid(b.serial_unit_id))
  return NextResponse.json({error:"A valid order line and serialized inventory unit are required."},{status:400,headers});
 const {baseUrl,serviceKey,personId}=auth.context;
 const r=await fetch(baseUrl+"/rest/v1/rpc/mme_pos_assign_serial_unit_to_order_line",{
  method:"POST",headers:{apikey:serviceKey,Authorization:"Bearer "+serviceKey,"Content-Type":"application/json"},
  body:JSON.stringify({p_order_line_id:b.order_line_id,p_serial_unit_id:b.serial_unit_id,p_actor_person_id:personId}),cache:"no-store"
 });
 if(!r.ok)return NextResponse.json({error:"Serial unit assignment failed. Verify store access, product match and inventory availability."},{status:r.status===403?403:409,headers});
 return NextResponse.json({assigned:await r.json()===true},{headers});
}
