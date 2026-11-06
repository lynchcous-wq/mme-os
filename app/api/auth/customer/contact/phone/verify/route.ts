import {NextRequest,NextResponse} from "next/server";
import {requireBrowserUser,hasSameOrigin,supabaseConfig,setSessionCookies} from "@/lib/auth/supabase-session";
export const dynamic="force-dynamic";
const headers={"Cache-Control":"no-store, max-age=0"};
export async function POST(request:NextRequest){
 if(!hasSameOrigin(request))return NextResponse.json({error:"Request origin could not be verified."},{status:403,headers});
 if(!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))return NextResponse.json({error:"A JSON request is required."},{status:415,headers});
 const session=await requireBrowserUser(request);
 if(!session.user)return NextResponse.json({error:"Sign in again to verify your phone."},{status:401,headers});
 let body:Record<string,unknown>;try{body=await request.json();}catch{return NextResponse.json({error:"Invalid request."},{status:400,headers});}
 const phone=typeof body.phone==="string"?body.phone.trim():"",token=typeof body.token==="string"?body.token.trim():"";
 if(!/^\+[1-9]\d{7,14}$/.test(phone)||!/^[0-9]{4,10}$/.test(token))return NextResponse.json({error:"Enter the phone number and verification code."},{status:400,headers});
 try{
  const {url,anon}=supabaseConfig(),access=request.cookies.get("mme_access_token")?.value;
  if(!access)return NextResponse.json({error:"Sign in again to verify your phone."},{status:401,headers});
  const r=await fetch(url+"/auth/v1/verify",{method:"POST",headers:{apikey:anon,Authorization:"Bearer "+access,"Content-Type":"application/json"},body:JSON.stringify({phone,token,type:"phone_change"}),cache:"no-store"});
  if(!r.ok)return NextResponse.json({error:"The verification code is invalid or expired."},{status:400,headers});
  const verified=await r.json();
  if(!verified.access_token||!verified.refresh_token)return NextResponse.json({error:"The provider did not return a verified session."},{status:502,headers});
  const response=NextResponse.json({verified:true,message:"Phone number verified."},{headers});
  setSessionCookies(response,verified);
  return response;
 }catch{return NextResponse.json({error:"Phone verification is temporarily unavailable."},{status:503,headers});}
}
