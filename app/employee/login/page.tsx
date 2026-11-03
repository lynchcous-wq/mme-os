"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

export default function EmployeeLoginPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const setupRequired = searchParams.get("setup") === "required";

  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setLoading(true);
    try {
      const supabase = createClient();
      const { error: authError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
      if (authError) throw authError;
      const requested = searchParams.get("next") ?? "/employee/catalog";
      const safeNext = requested.startsWith("/employee/") && !requested.startsWith("//") ? requested : "/employee/catalog";
      router.replace(safeNext);
      router.refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Sign-in failed. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main style={{minHeight:"100vh",display:"grid",placeItems:"center",padding:24,background:"#f3f0e9"}}>
      <section style={{width:"100%",maxWidth:420,background:"#fff",padding:32,border:"1px solid #ddd",borderRadius:8}}>
        <Link href="/" style={{color:"#273d52",fontWeight:700,textDecoration:"none"}}>MUCH MORE ELECTRONICS</Link>
        <p style={{fontSize:11,letterSpacing:2,color:"#68727b",marginTop:28}}>MME OS · EMPLOYEE ACCESS</p>
        <h1 style={{fontSize:30,margin:"8px 0 10px"}}>Employee sign in</h1>
        <p style={{fontSize:13,lineHeight:1.7,color:"#626b73"}}>Use your company-issued account. Employee access must be provisioned by an authorized administrator.</p>
        {setupRequired && <p role="alert" style={{padding:12,background:"#fff4df",color:"#75501a",fontSize:12}}>Supabase environment settings are missing. Configure the project URL and publishable/anon key in the deployment environment.</p>}
        <form onSubmit={signIn} style={{display:"grid",gap:14,marginTop:22}}>
          <label style={{display:"grid",gap:6,fontSize:12,fontWeight:600}}>Work email<input required type="email" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} style={fieldStyle}/></label>
          <label style={{display:"grid",gap:6,fontSize:12,fontWeight:600}}>Password<input required type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} style={fieldStyle}/></label>
          {error && <p role="alert" style={{color:"#a22",fontSize:12,margin:0}}>{error}</p>}
          <button disabled={loading || setupRequired} type="submit" style={{padding:13,border:0,borderRadius:4,background:"#193b55",color:"#fff",fontWeight:700,cursor:"pointer",opacity:loading || setupRequired ? .6 : 1}}>{loading ? "Signing in…" : "Sign in securely"}</button>
        </form>
        <p style={{fontSize:11,lineHeight:1.7,color:"#737b82",marginTop:20}}>No public employee registration. Access remains subject to MME employee status, permissions and company security controls.</p>
      </section>
    </main>
  );
}

const fieldStyle = {width:"100%",padding:12,border:"1px solid #cfd4d8",borderRadius:4,fontSize:14} as const;
