import {NextRequest,NextResponse} from "next/server";
import {requireBrowserUser,hasSameOrigin,supabaseConfig,setSessionCookies} from "@/lib/auth/supabase-session";
export const dynamic="force-dynamic";
const headers={"Cache-Control":"no-store, max-age=0"};
export async function POST(request:NextRequest){
 if(!hasSameOrigin(request))return NextResponse.json({error:"Request origin could not be verified."},{status:403,headers});
 if(!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))return NextResponse.json({error:"A JSON request is required."},{status:415,headers});
 const session=await requireBrowserUser(request);
 if(!session.user)return NextResponse.json({error:"Sign in again to change your email."},{status:401,headers});
 let body:Record<string,unknown>;try{body=await request.json();}catch{return NextResponse.json({error:"Invalid request."},{status:400,headers});}
 const email=typeof body.email==="string"?body.email.trim().toLowerCase():"";
 if(email.length>320||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return NextResponse.json({error:"Enter a valid email address."},{status:400,headers});
 try{
  const {url,anon}=supabaseConfig(),access=request.cookies.get("mme_access_token")?.value;
  if(!access)return NextResponse.json({error:"Sign in again to change your email."},{status:401,headers});
  const r=await fetch(url+"/auth/v1/user",{method:"PUT",headers:{apikey:anon,Authorization:"Bearer "+access,"Content-Type":"application/json"},body:JSON.stringify({email}),cache:"no-store"});
  if(!r.ok)return NextResponse.json({message:"If this address can be updated, the authentication provider will send its required confirmation message. Your sign-in email remains unchanged until confirmation."},{headers});
  const response=NextResponse.json({message:"Confirmation instructions have been requested. Your current sign-in email remains active until the new address is verified."},{headers});
  if(session.refreshed)setSessionCookies(response,session.refreshed);
  return response;
 }catch{return NextResponse.json({error:"Email change is temporarily unavailable."},{status:503,headers});}
}
