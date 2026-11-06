import {NextRequest,NextResponse} from "next/server";
import {requireBrowserUser,hasSameOrigin,supabaseConfig} from "@/lib/auth/supabase-session";
export const dynamic="force-dynamic";
const headers={"Cache-Control":"no-store, max-age=0"};
export async function POST(request:NextRequest){
 if(!hasSameOrigin(request))return NextResponse.json({error:"Request origin could not be verified."},{status:403,headers});
 if(!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))return NextResponse.json({error:"A JSON request is required."},{status:415,headers});
 const session=await requireBrowserUser(request);
 if(!session.user)return NextResponse.json({error:"Sign in again to verify a phone number."},{status:401,headers});
 let body:Record<string,unknown>;try{body=await request.json();}catch{return NextResponse.json({error:"Invalid request."},{status:400,headers});}
 const phone=typeof body.phone==="string"?body.phone.trim():"";
 if(!/^\+[1-9]\d{7,14}$/.test(phone))return NextResponse.json({error:"Enter a valid phone number in international format, such as +14045550123."},{status:400,headers});
 try{
  const {url,anon}=supabaseConfig(),access=request.cookies.get("mme_access_token")?.value;
  if(!access)return NextResponse.json({error:"Sign in again to verify a phone number."},{status:401,headers});
  const r=await fetch(url+"/auth/v1/user",{method:"PUT",headers:{apikey:anon,Authorization:"Bearer "+access,"Content-Type":"application/json"},body:JSON.stringify({phone}),cache:"no-store"});
  if(!r.ok)return NextResponse.json({error:"Phone verification could not be started. Check the number or try again later."},{status:409,headers});
  return NextResponse.json({message:"If phone authentication is enabled for this Supabase project, a verification code has been requested. Your phone is not considered verified until the provider confirms the code."},{headers});
 }catch{return NextResponse.json({error:"Phone verification is temporarily unavailable."},{status:503,headers});}
}
