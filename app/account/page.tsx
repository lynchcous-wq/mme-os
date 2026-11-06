"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";

export default function AccountPage() {
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
        body: JSON.stringify({ email, password }),
      });
      const result = await response.json() as { error?: string };
      if (!response.ok) throw new Error(result.error || "Sign-in failed.");
      const access = await fetch("/api/auth/customer", { credentials: "same-origin", cache: "no-store" });
      const accessResult = await access.json() as { error?: string; customerAccess?: boolean };
      if (!access.ok) {
        setMessage(accessResult.error || "Your login is valid, but a customer account link has not been provisioned yet. Contact MME support.");
      } else {
        setSignedIn(true);
        setMessage("You're signed in. Your customer account access is active.");
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to sign in right now.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main style={{ minHeight: "100vh", display: "grid", placeItems: "center", background: "#f4f6f8", padding: 20, color: "#172432" }}>
      <section style={{ width: "min(100%, 440px)", background: "#fff", padding: 32, borderRadius: 14, border: "1px solid #e1e6eb", boxShadow: "0 12px 40px rgba(20,40,60,.08)" }}>
        <Link href="/" style={{ color: "#173f58", fontWeight: 800, textDecoration: "none", letterSpacing: 1 }}>MUCH MORE ELECTRONICS</Link>
        <p style={{ marginTop: 30, color: "#607180", fontSize: 12, letterSpacing: 1.5, fontWeight: 700 }}>CUSTOMER ACCOUNT</p>
        <h1 style={{ fontSize: 32, margin: "8px 0" }}>Welcome back.</h1>
        <p style={{ color: "#607180", lineHeight: 1.5 }}>Sign in to access your MME customer account.</p>
        <form onSubmit={submit} style={{ display: "grid", gap: 14, marginTop: 24 }}>
          <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Email
            <input type="email" autoComplete="username" required maxLength={320} value={email} onChange={e => setEmail(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
          </label>
          <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Password
            <input type="password" autoComplete="current-password" required maxLength={1024} value={password} onChange={e => setPassword(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
          </label>
          <button disabled={busy} type="submit" style={{ padding: 14, background: "#173f58", color: "#fff", border: 0, borderRadius: 8, fontWeight: 700, cursor: busy ? "wait" : "pointer" }}>{busy ? "Signing in…" : "Sign in"}</button>
        </form>
        {message && <p role="status" aria-live="polite" style={{ marginTop: 18, padding: 12, background: "#f3f6f8", borderRadius: 8, lineHeight: 1.5 }}>{message}</p>}
        {signedIn && <button type="button" onClick={async () => { const response = await fetch("/api/auth/sign-out", { method: "POST", credentials: "same-origin" }); if (response.ok) { setSignedIn(false); setMessage("You have been signed out."); } }} style={{ marginTop: 14, padding: 10, border: "1px solid #cbd4dc", borderRadius: 8, background: "#fff", color: "#173f58" }}>Sign out</button>}
        <p style={{ marginTop: 24, color: "#607180", fontSize: 13 }}>Need help? Contact MME support. Registration and password recovery are not enabled in this release.</p>
        <p style={{ marginTop: 20, fontSize: 13 }}><Link href="/employee/sign-in" style={{ color: "#1b7181" }}>Employee sign-in</Link> · <Link href="/products" style={{ color: "#1b7181" }}>Continue shopping</Link></p>
      </section>
    </main>
  );
}
