import {NextRequest,NextResponse} from "next/server";
import {requireBrowserUser,clearSessionCookies,setSessionCookies,supabaseConfig,hasSameOrigin} from "@/lib/auth/supabase-session";
export const dynamic="force-dynamic";
const headers={"Cache-Control":"no-store, max-age=0",Vary:"Cookie"};
async function appendEvent(userId:string,eventType:"sessions_revoked"){
 const {url}=supabaseConfig(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 if(!key)return;
 await fetch(url+"/rest/v1/mme_customer_security_events",{method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json",Prefer:"return=minimal"},body:JSON.stringify({auth_user_id:userId,event_type:eventType,event_source:"customer_portal",event_details:{scope:"global"}}),cache:"no-store"});
}
export async function GET(request:NextRequest){
 try{
  const session=await requireBrowserUser(request);
  if(!session.user)return NextResponse.json({error:"Sign in to view security settings."},{status:401,headers});
  const {url}=supabaseConfig(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!key)return NextResponse.json({error:"Security history is not configured."},{status:503,headers});
  const r=await fetch(url+"/rest/v1/mme_customer_security_events?auth_user_id=eq."+encodeURIComponent(session.user.id)+"&select=event_id,event_type,event_source,event_details,created_at&order=created_at.desc&limit=25",{headers:{apikey:key,Authorization:"Bearer "+key},cache:"no-store"});
  if(!r.ok)return NextResponse.json({error:"Security history is temporarily unavailable."},{status:503,headers});
  const events=await r.json();
  const response=NextResponse.json({account:{email:session.user.email??null,emailVerified:Boolean(session.user.email_confirmed_at)},currentSession:{status:"authenticated",management:"Current browser session only"},sessions:[],sessionListingAvailable:false,globalRevocationAvailable:true,events},{headers});
  if(session.refreshed)setSessionCookies(response,session.refreshed);
  return response;
 }catch{return NextResponse.json({error:"Security settings are temporarily unavailable."},{status:503,headers});}
}
export async function POST(request:NextRequest){
 if(!hasSameOrigin(request))return NextResponse.json({error:"Request origin could not be verified."},{status:403,headers});
 if(!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))return NextResponse.json({error:"A JSON request is required."},{status:415,headers});
 const session=await requireBrowserUser(request);
 if(!session.user)return NextResponse.json({error:"Sign in again to manage sessions."},{status:401,headers});
 let body:Record<string,unknown>;try{body=await request.json();}catch{return NextResponse.json({error:"Invalid request."},{status:400,headers});}
 if(body.action!=="revoke_all")return NextResponse.json({error:"Unsupported security action."},{status:400,headers});
 try{
  const {url,anon}=supabaseConfig(),access=session.refreshed?.access_token??request.cookies.get("mme_access_token")?.value;
  if(!access)return NextResponse.json({error:"Sign in again before revoking sessions."},{status:401,headers});
  const r=await fetch(url+"/auth/v1/logout?scope=global",{method:"POST",headers:{apikey:anon,Authorization:"Bearer "+access},cache:"no-store"});
  if(!r.ok)return NextResponse.json({error:"The authentication provider could not revoke sessions. Please try again."},{status:502,headers});
  await appendEvent(session.user.id,"sessions_revoked").catch(()=>undefined);
  const response=NextResponse.json({revoked:true,message:"A global sign-out was requested from the authentication provider. Existing access tokens may remain valid until their short expiry; sign in again on this device."},{headers});
  clearSessionCookies(response);
  return response;
 }catch{return NextResponse.json({error:"Session revocation is temporarily unavailable."},{status:503,headers});}
}
