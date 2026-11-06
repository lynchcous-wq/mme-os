import {NextRequest,NextResponse} from "next/server";
import {hasSameOrigin,supabaseConfig} from "@/lib/auth/supabase-session";
export const dynamic="force-dynamic";
const headers={"Cache-Control":"no-store, max-age=0"};
export async function POST(request:NextRequest){
 if(!hasSameOrigin(request))return NextResponse.json({error:"Request origin could not be verified."},{status:403,headers});
 if(!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))return NextResponse.json({error:"A JSON request is required."},{status:415,headers});
 let body:Record<string,unknown>;try{body=await request.json();}catch{return NextResponse.json({error:"Invalid request."},{status:400,headers});}
 const email=typeof body.email==="string"?body.email.trim().toLowerCase():"";
 if(email.length>320||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return NextResponse.json({error:"Enter a valid email address."},{status:400,headers});
 try{
  const {url,anon}=supabaseConfig();
  await fetch(url+"/auth/v1/recover",{method:"POST",headers:{apikey:anon,"Content-Type":"application/json"},body:JSON.stringify({email,redirect_to:new URL("/account/recovery",request.nextUrl.origin).toString()}),cache:"no-store"});
  return NextResponse.json({message:"If an account exists for that address, recovery instructions will be sent."},{headers});
 }catch{return NextResponse.json({message:"If an account exists for that address, recovery instructions will be sent."},{headers});}
}
