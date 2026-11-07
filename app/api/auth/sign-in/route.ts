import {NextRequest,NextResponse} from "next/server";
import {hasSameOrigin,passwordSignIn,setSessionCookies,supabaseConfig} from "@/lib/auth/supabase-session";
export const dynamic="force-dynamic";
export async function POST(request:NextRequest){
 if(!hasSameOrigin(request))return NextResponse.json({error:"Request origin could not be verified."},{status:403});
 if(!request.headers.get("content-type")?.toLowerCase().includes("application/json"))return NextResponse.json({error:"JSON request required."},{status:415});
 try{
  const body=await request.json() as {email?:unknown;password?:unknown};
  if(typeof body.email!=="string"||typeof body.password!=="string"||body.email.length>320||body.password.length<1||body.password.length>1024)return NextResponse.json({error:"Enter a valid email and password."},{status:400});
  const session=await passwordSignIn(body.email.trim(),body.password);
  if(session.user?.id){const {url}=supabaseConfig(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(key)await fetch(url+"/rest/v1/mme_customer_security_events",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json",Prefer:"return=minimal"},body:JSON.stringify({auth_user_id:session.user.id,event_type:"sign_in_success",event_source:"mme_portal",event_details:{channel:"password"}}),cache:"no-store"}).catch(()=>undefined);}
  const response=NextResponse.json({authenticated:true,user:{id:session.user?.id??null,email:session.user?.email??body.email.trim()}},{headers:{"Cache-Control":"no-store"}});
  setSessionCookies(response,session);return response;
 }catch{return NextResponse.json({error:"Sign-in failed. Check your credentials or try again later."},{status:401,headers:{"Cache-Control":"no-store"}});}
}
