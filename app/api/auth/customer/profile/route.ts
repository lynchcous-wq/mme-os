import {NextRequest,NextResponse} from "next/server";
import {requireBrowserUser,setSessionCookies,supabaseConfig,hasSameOrigin} from "@/lib/auth/supabase-session";
export const dynamic="force-dynamic";
const headers={"Cache-Control":"no-store, max-age=0",Vary:"Cookie"};
export async function GET(request:NextRequest){
 try{
  const session=await requireBrowserUser(request);
  if(!session.user)return NextResponse.json({error:"Sign in to manage your profile."},{status:401,headers});
  const {url}=supabaseConfig(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!key)return NextResponse.json({error:"Profile service is not configured."},{status:503,headers});
  const link=await fetch(url+"/rest/v1/mme_customer_account_links?auth_user_id=eq."+encodeURIComponent(session.user.id)+"&link_status=eq.active&select=person_id&limit=2",{headers:{apikey:key,Authorization:"Bearer "+key},cache:"no-store"});
  if(!link.ok)return NextResponse.json({error:"Customer identity could not be verified."},{status:503,headers});
  const links=await link.json();
  if(links.length!==1)return NextResponse.json({error:"An active MME customer identity is required to manage this profile."},{status:403,headers});
  const identity=await fetch(url+"/rest/v1/mme_person_identities?person_id=eq."+encodeURIComponent(links[0].person_id)+"&lifecycle_status=eq.active&select=person_id&limit=1",{headers:{apikey:key,Authorization:"Bearer "+key},cache:"no-store"});
  if(!identity.ok)return NextResponse.json({error:"Customer identity could not be verified."},{status:503,headers});
  if((await identity.json()).length!==1)return NextResponse.json({error:"An active MME customer identity is required to manage this profile."},{status:403,headers});
  const r=await fetch(url+"/rest/v1/mme_customer_profiles?auth_user_id=eq."+encodeURIComponent(session.user.id)+"&select=preferred_name,email_notifications_enabled,sms_notifications_enabled&limit=1",{headers:{apikey:key,Authorization:"Bearer "+key},cache:"no-store"});
  if(!r.ok)return NextResponse.json({error:"Profile could not be loaded."},{status:503,headers});
  const rows=await r.json();
  const response=NextResponse.json({email:session.user.email??null,emailVerified:Boolean(session.user.email_confirmed_at),profile:rows[0]??{preferred_name:null,email_notifications_enabled:true,sms_notifications_enabled:false}},{headers});
  if(session.refreshed)setSessionCookies(response,session.refreshed);
  return response;
 }catch{return NextResponse.json({error:"Profile service is temporarily unavailable."},{status:503,headers});}
}
export async function PATCH(request:NextRequest){
 if(!hasSameOrigin(request))return NextResponse.json({error:"Request origin could not be verified."},{status:403,headers});
 if(!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))return NextResponse.json({error:"A JSON request is required."},{status:415,headers});
 const session=await requireBrowserUser(request);
 if(!session.user)return NextResponse.json({error:"Sign in to manage your profile."},{status:401,headers});
 let body:Record<string,unknown>;try{body=await request.json();}catch{return NextResponse.json({error:"Invalid request body."},{status:400,headers});}
 const name=body.preferredName;
 if(name!==null&&typeof name!=="string")return NextResponse.json({error:"Preferred name must be text or blank."},{status:400,headers});
 const preferredName=typeof name==="string"?name.trim():null;
 if(preferredName!==null&&(preferredName.length<1||preferredName.length>80||/[\u0000-\u001f\u007f]/.test(preferredName)))return NextResponse.json({error:"Preferred name must be 1–80 printable characters."},{status:400,headers});
 if(typeof body.emailNotificationsEnabled!=="boolean"||typeof body.smsNotificationsEnabled!=="boolean")return NextResponse.json({error:"Choose both notification preferences."},{status:400,headers});
 try{
  const {url}=supabaseConfig(),anon=process.env.SUPABASE_ANON_KEY??process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if(!anon)return NextResponse.json({error:"Profile service is not configured."},{status:503,headers});
  const access=request.cookies.get("mme_access_token")?.value;
  if(!access)return NextResponse.json({error:"Sign in again to update your profile."},{status:401,headers});
  const r=await fetch(url+"/rest/v1/rpc/mme_customer_profile_update",{method:"POST",headers:{apikey:anon,Authorization:"Bearer "+access,"Content-Type":"application/json"},body:JSON.stringify({p_auth_user_id:session.user.id,p_preferred_name:preferredName,p_email_notifications_enabled:body.emailNotificationsEnabled,p_sms_notifications_enabled:body.smsNotificationsEnabled}),cache:"no-store"});
  if(!r.ok)return NextResponse.json({error:r.status===401||r.status===403?"Your verified customer session is required.":"Profile changes could not be saved."},{status:r.status===401||r.status===403?403:409,headers});
  const profile=await r.json();
  const response=NextResponse.json({profile},{headers});
  if(session.refreshed)setSessionCookies(response,session.refreshed);
  return response;
 }catch{return NextResponse.json({error:"Profile service is temporarily unavailable."},{status:503,headers});}
}
