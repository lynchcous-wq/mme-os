import {NextRequest,NextResponse} from "next/server";
import {requireBrowserUser,setSessionCookies,supabaseConfig,hasSameOrigin} from "@/lib/auth/supabase-session";
export const dynamic="force-dynamic";
const headers={"Cache-Control":"no-store, max-age=0",Vary:"Cookie"};
export async function GET(request:NextRequest){
 try{
  const session=await requireBrowserUser(request);
  if(!session.user)return NextResponse.json({error:"Sign in to manage security alerts."},{status:401,headers});
  const {url}=supabaseConfig(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!key)return NextResponse.json({error:"Security alert preferences are not configured."},{status:503,headers});
  const r=await fetch(url+"/rest/v1/mme_customer_security_alert_preferences?auth_user_id=eq."+encodeURIComponent(session.user.id)+"&select=email_alerts_enabled&limit=1",{headers:{apikey:key,Authorization:"Bearer "+key},cache:"no-store"});
  if(!r.ok)return NextResponse.json({error:"Security alert preferences are unavailable."},{status:503,headers});
  const rows=await r.json(),response=NextResponse.json({emailAlertsEnabled:rows[0]?.email_alerts_enabled??true},{headers});
  if(session.refreshed)setSessionCookies(response,session.refreshed);return response;
 }catch{return NextResponse.json({error:"Security alert preferences are temporarily unavailable."},{status:503,headers});}
}
export async function PATCH(request:NextRequest){
 if(!hasSameOrigin(request))return NextResponse.json({error:"Request origin could not be verified."},{status:403,headers});
 if(!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))return NextResponse.json({error:"A JSON request is required."},{status:415,headers});
 const session=await requireBrowserUser(request);
 if(!session.user)return NextResponse.json({error:"Sign in again to update security alerts."},{status:401,headers});
 let body:Record<string,unknown>;try{body=await request.json();}catch{return NextResponse.json({error:"Invalid request."},{status:400,headers});}
 if(typeof body.emailAlertsEnabled!=="boolean")return NextResponse.json({error:"Choose whether to receive account-security emails."},{status:400,headers});
 try{
  const {url,anon}=supabaseConfig(),access=session.refreshed?.access_token??request.cookies.get("mme_access_token")?.value;
  if(!access)return NextResponse.json({error:"Sign in again to update security alerts."},{status:401,headers});
  const r=await fetch(url+"/rest/v1/rpc/mme_customer_security_alert_preference_update",{method:"POST",headers:{apikey:anon,Authorization:"Bearer "+access,"Content-Type":"application/json"},body:JSON.stringify({p_auth_user_id:session.user.id,p_enabled:body.emailAlertsEnabled}),cache:"no-store"});
  if(!r.ok)return NextResponse.json({error:"Security alert preference could not be saved. Verify your customer account and try again."},{status:r.status===401||r.status===403?403:409,headers});
  const preference=await r.json(),response=NextResponse.json({emailAlertsEnabled:preference.email_alerts_enabled},{headers});
  if(session.refreshed)setSessionCookies(response,session.refreshed);return response;
 }catch{return NextResponse.json({error:"Security alert preference service is temporarily unavailable."},{status:503,headers});}
}
