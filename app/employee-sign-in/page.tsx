"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";

type Mode = "signin" | "register";

export default function EmployeeSignInPage() {
  const [mode, setMode] = useState<Mode>("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");
  const [showAdminClaim, setShowAdminClaim] = useState(false);
  const [busy, setBusy] = useState(false);
  const [signedIn, setSignedIn] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch(mode === "register" ? "/api/auth/employee-sign-up" : "/api/auth/sign-in", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        body: JSON.stringify({ email, password }),
      });
      const result = await response.json() as { error?: string; message?: string; authenticated?: boolean };
      if (mode === "register") {
        if (!response.ok && response.status !== 202) throw new Error(result.error || "Account registration could not be submitted.");
        setMessage(result.message || "Check your email for a confirmation link. Employee access requires a separately approved MME employee identity.");
        setPassword("");
      } else {
        if (!response.ok || !result.authenticated) throw new Error(result.error || "Employee sign-in failed.");
        setSignedIn(true);
        setPassword("");
        setMessage("Your active MME employee identity has been verified. Your secure sign-in session is active.");
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to complete your request.");
    } finally {
      setBusy(false);
    }
  }

  async function signOut() {
    setBusy(true);
    try {
      const response = await fetch("/api/auth/sign-out", { method: "POST", credentials: "same-origin" });
      if (!response.ok) throw new Error("Sign-out could not be completed.");
      setSignedIn(false);
      setMessage("You have been signed out.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Sign-out could not be completed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main style={{ minHeight: "100vh", display: "grid", placeItems: "center", background: "#edf2f5", padding: 20, color: "#172432" }}>
      <section style={{ width: "min(100%, 480px)", background: "#fff", padding: 32, borderRadius: 14, border: "1px solid #dce4e9", boxShadow: "0 16px 48px rgba(20,40,55,.08)" }}>
        <Link href="/" style={{ color: "#173f58", fontWeight: 800, textDecoration: "none", letterSpacing: 1 }}>MME · EMPLOYEE ACCESS</Link>
        <p style={{ marginTop: 30, color: "#607180", fontSize: 12, letterSpacing: 1.5, fontWeight: 700 }}>SECURE STAFF ACCESS</p>
        <h1 style={{ fontSize: 32, margin: "8px 0" }}>Employee portal.</h1>
        <p style={{ color: "#607180", lineHeight: 1.5 }}>Sign in with your assigned MME work account or create an account. New accounts do not receive employee or administrator permissions until identity and role approval are complete.</p>
        {!signedIn ? (
          <>
            <div role="group" aria-label="Employee account action" style={{ display: "flex", gap: 10, margin: "24px 0 20px", flexWrap: "wrap" }}>
              <button type="button" onClick={() => { setMode("signin"); setMessage(""); }} aria-pressed={mode === "signin"} style={{ padding: "11px 16px", border: "1px solid #173f58", background: mode === "signin" ? "#173f58" : "white", color: mode === "signin" ? "white" : "#173f58", borderRadius: 8, cursor: "pointer" }}>Sign in</button>
              <button type="button" onClick={() => { setMode("register"); setMessage(""); }} aria-pressed={mode === "register"} style={{ padding: "11px 16px", border: "1px solid #173f58", background: mode === "register" ? "#173f58" : "white", color: mode === "register" ? "white" : "#173f58", borderRadius: 8, cursor: "pointer" }}>Create user</button>
              <button type="button" onClick={() => setShowAdminClaim(v => !v)} aria-expanded={showAdminClaim} style={{ padding: "11px 16px", border: "1px solid #a88a50", background: "#fffaf0", color: "#70551f", borderRadius: 8, cursor: "pointer" }}>Claim admin role</button>
            </div>
            {showAdminClaim && <div style={{ padding: 16, border: "1px solid #e6d8b7", background: "#fffaf0", borderRadius: 8, marginBottom: 18, lineHeight: 1.55 }}>
              <b style={{ display: "block", marginBottom: 6 }}>Platform administrator verification</b>
              <span style={{ color: "#66583b", fontSize: 13 }}>Admin claims are restricted to the verified, invited CEO identity. Creating a user or selecting this option never grants administrator access. Complete the CEO email invitation first; the platform will then verify the confirmed account, match its MME identity, and provision the CEO role through the audited approval process.</span>
            </div>}
            <form onSubmit={submit} style={{ display: "grid", gap: 14 }}>
              <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Work email
                <input type="email" autoComplete="email" required maxLength={320} value={email} onChange={e => setEmail(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
              </label>
              <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Password
                <input type="password" autoComplete={mode === "register" ? "new-password" : "current-password"} required minLength={mode === "register" ? 12 : 1} maxLength={1024} value={password} onChange={e => setPassword(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
              </label>
              {mode === "register" && <small style={{ color: "#607180", lineHeight: 1.5 }}>Use at least 12 characters. Confirm your email, then have MME verify and activate your employee identity.</small>}
              <button disabled={busy} type="submit" style={{ padding: 14, background: "#173f58", color: "#fff", border: 0, borderRadius: 8, fontWeight: 700, cursor: busy ? "wait" : "pointer" }}>{busy ? "Please wait…" : mode === "register" ? "Create employee user" : "Sign in securely"}</button>
            </form>
          </>
        ) : (
          <button type="button" disabled={busy} onClick={signOut} style={{ marginTop: 24, padding: 12, border: "1px solid #cbd4dc", borderRadius: 8, background: "#fff", color: "#173f58", fontWeight: 700 }}>Sign out</button>
        )}
        {message && <p role="status" aria-live="polite" style={{ marginTop: 18, padding: 12, background: "#f3f6f8", borderRadius: 8, lineHeight: 1.5 }}>{message}{signedIn && <span style={{ display: "block", marginTop: 12 }}><Link href="/employee/financing/providers" style={{ color: "#1b7181", fontWeight: 700 }}>Open Financing Provider Center →</Link></span>}</p>}
        <p style={{ marginTop: 24, fontSize: 13 }}><Link href="/account" style={{ color: "#1b7181" }}>Customer account</Link> · <Link href="/" style={{ color: "#1b7181" }}>Back to store</Link></p>
      </section>
    </main>
  );
}
