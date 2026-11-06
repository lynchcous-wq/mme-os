import {NextRequest,NextResponse} from "next/server";
import {hasSameOrigin,supabaseConfig,setSessionCookies} from "@/lib/auth/supabase-session";
export const dynamic="force-dynamic";
const headers={"Cache-Control":"no-store, max-age=0"};
export async function POST(request:NextRequest){
 if(!hasSameOrigin(request))return NextResponse.json({error:"Request origin could not be verified."},{status:403,headers});
 if(!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))return NextResponse.json({error:"A JSON request is required."},{status:415,headers});
 let body:Record<string,unknown>;try{body=await request.json();}catch{return NextResponse.json({error:"Invalid request."},{status:400,headers});}
 const password=typeof body.password==="string"?body.password:"",token=typeof body.token==="string"?body.token.trim():"";
 if(password.length<12||password.length>128||!/[a-z]/.test(password)||!/[A-Z]/.test(password)||!/[0-9]/.test(password)||!/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>/?]/.test(password))return NextResponse.json({error:"Use 12–128 characters with upper/lowercase letters, a number, and a symbol."},{status:400,headers});
 if(!/^[A-Za-z0-9_-]{20,512}$/.test(token))return NextResponse.json({error:"Recovery link is invalid or expired."},{status:400,headers});
 try{
  const {url,anon}=supabaseConfig();
  const verify=await fetch(url+"/auth/v1/verify",{method:"POST",headers:{apikey:anon,"Content-Type":"application/json"},body:JSON.stringify({token_hash:token,type:"recovery"}),cache:"no-store"});
  if(!verify.ok)return NextResponse.json({error:"Recovery link is invalid or expired."},{status:400,headers});
  const session=await verify.json();
  if(typeof session.access_token!=="string"||typeof session.refresh_token!=="string")return NextResponse.json({error:"Recovery session could not be established."},{status:502,headers});
  const update=await fetch(url+"/auth/v1/user",{method:"PUT",headers:{apikey:anon,Authorization:"Bearer "+session.access_token,"Content-Type":"application/json"},body:JSON.stringify({password}),cache:"no-store"});
  if(!update.ok)return NextResponse.json({error:"Password could not be updated. Request a new recovery link."},{status:400,headers});
  const response=NextResponse.json({updated:true,message:"Password updated. Sign in with your new password."},{headers});
  return response;
 }catch{return NextResponse.json({error:"Account recovery is temporarily unavailable."},{status:503,headers});}
}
