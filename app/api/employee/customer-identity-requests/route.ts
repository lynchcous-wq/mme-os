import { NextRequest, NextResponse } from "next/server";
import { requireCustomerIdentityReviewer } from "@/lib/auth/customer-identity-review";
import { setSessionCookies, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
 const access = await requireCustomerIdentityReviewer(request);
 if (!access.authorized) return NextResponse.json({error:access.status===403?"You do not have permission to review customer identity requests.":"Employee review service is unavailable."},{status:access.status,headers:{"Cache-Control":"no-store"}});
 try {
  const {url}=supabaseConfig(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!key) return NextResponse.json({error:"Review service is not configured."},{status:503});
  const response=await fetch(`${url}/rest/v1/mme_customer_identity_link_requests?request_status=in.(pending,under_review)&select=request_id,verified_email,customer_reference,contact_phone_last4,customer_note,request_status,requested_at,reviewed_by_auth_user_id,review_note&order=requested_at.asc&limit=100`,{
   headers:{apikey:key!,Authorization:`Bearer ${key}`},cache:"no-store"
  });
  if(!response.ok) return NextResponse.json({error:"Could not load the review queue."},{status:503});
  const result=NextResponse.json({requests:await response.json()},{headers:{"Cache-Control":"no-store"}});
  if(access.refreshed) setSessionCookies(result,access.refreshed);
  return result;
 } catch {return NextResponse.json({error:"Review service is temporarily unavailable."},{status:503});}
}

export async function POST(request:NextRequest){
 if(!request.headers.get("origin")||new URL(request.headers.get("origin")!).host!==request.nextUrl.host)
  return NextResponse.json({error:"Request origin could not be verified."},{status:403});
 if(!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))
  return NextResponse.json({error:"A JSON request is required."},{status:415});
 const access=await requireCustomerIdentityReviewer(request);
 if(!access.authorized) return NextResponse.json({error:"You do not have permission to review customer identity requests."},{status:access.status});
 let input:{requestId?:unknown;decision?:unknown;personId?:unknown;note?:unknown};
 try{input=await request.json();}catch{return NextResponse.json({error:"Invalid request body."},{status:400});}
 const requestId=typeof input.requestId==="string"?input.requestId:"";
 const decision=typeof input.decision==="string"?input.decision:"";
 const personId=typeof input.personId==="string"?input.personId:"";
 const note=typeof input.note==="string"?input.note.trim():"";
 const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
 if(!uuid.test(requestId)||!["under_review","approve","reject"].includes(decision)||(decision==="approve"&&!uuid.test(personId))||note.length>1000)
  return NextResponse.json({error:"Check the request, decision, identity, and note fields."},{status:400});
 try{
  const {url}=supabaseConfig(),key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!key) return NextResponse.json({error:"Review service is not configured."},{status:503});
  const response=await fetch(`${url}/rest/v1/rpc/mme_customer_identity_review_decide`,{
   method:"POST",headers:{apikey:key,Authorization:`Bearer ${key}`,"Content-Type":"application/json"},
   body:JSON.stringify({p_actor_auth_user_id:access.user!.id,p_request_id:requestId,p_decision:decision,p_person_id:decision==="approve"?personId:null,p_review_note:note||null}),cache:"no-store"
  });
  const body=await response.json().catch(()=>({}));
  if(!response.ok) return NextResponse.json({error:response.status===403?"You are not authorized to perform this review.":"The review decision could not be completed. Check the identity and request status."},{status:response.status===403?403:409,headers:{"Cache-Control":"no-store"}});
  const result=NextResponse.json({result:body},{headers:{"Cache-Control":"no-store"}});
  if(access.refreshed) setSessionCookies(result,access.refreshed);
  return result;
 }catch{return NextResponse.json({error:"Review service is temporarily unavailable."},{status:503});}
}
