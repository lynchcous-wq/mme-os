"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";

export default function EmployeeSignInPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [signedIn, setSignedIn] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch("/api/auth/sign-in", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        body: JSON.stringify({ email, password }),
      });
      const result = await response.json() as { error?: string; authenticated?: boolean };
      if (!response.ok || !result.authenticated) throw new Error(result.error || "Employee sign-in failed.");
      setSignedIn(true);
      setPassword("");
      setMessage("Your active MME employee identity has been verified. Your secure sign-in session is active.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to verify employee access.");
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
      <section style={{ width: "min(100%, 440px)", background: "#fff", padding: 32, borderRadius: 14, border: "1px solid #dce4e9", boxShadow: "0 16px 48px rgba(20,40,55,.08)" }}>
        <Link href="/" style={{ color: "#173f58", fontWeight: 800, textDecoration: "none", letterSpacing: 1 }}>MME · EMPLOYEE ACCESS</Link>
        <p style={{ marginTop: 30, color: "#607180", fontSize: 12, letterSpacing: 1.5, fontWeight: 700 }}>SECURE STAFF SIGN-IN</p>
        <h1 style={{ fontSize: 32, margin: "8px 0" }}>Employee portal.</h1>
        <p style={{ color: "#607180", lineHeight: 1.5 }}>Sign in with your assigned MME work account. Access is granted only after your active employee identity is verified.</p>
        {!signedIn ? (
          <form onSubmit={submit} style={{ display: "grid", gap: 14, marginTop: 24 }}>
            <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Work email
              <input type="email" autoComplete="username" required maxLength={320} value={email} onChange={e => setEmail(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
            </label>
            <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Password
              <input type="password" autoComplete="current-password" required maxLength={1024} value={password} onChange={e => setPassword(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
            </label>
            <button disabled={busy} type="submit" style={{ padding: 14, background: "#173f58", color: "#fff", border: 0, borderRadius: 8, fontWeight: 700, cursor: busy ? "wait" : "pointer" }}>{busy ? "Verifying…" : "Sign in securely"}</button>
          </form>
        ) : (
          <button type="button" disabled={busy} onClick={signOut} style={{ marginTop: 24, padding: 12, border: "1px solid #cbd4dc", borderRadius: 8, background: "#fff", color: "#173f58", fontWeight: 700 }}>Sign out</button>
        )}
        {message && <p role="status" aria-live="polite" style={{ marginTop: 18, padding: 12, background: "#f3f6f8", borderRadius: 8, lineHeight: 1.5 }}>{message}</p>}
        <p style={{ marginTop: 24, fontSize: 13 }}><Link href="/account" style={{ color: "#1b7181" }}>Customer account</Link> · <Link href="/" style={{ color: "#1b7181" }}>Back to store</Link></p>
      </section>
    </main>
  );
}
