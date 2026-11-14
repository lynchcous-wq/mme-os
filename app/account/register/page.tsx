"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";

export default function CustomerRegistrationPage() {
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [message, setMessage] = useState("");
  const [accepted, setAccepted] = useState(false);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");
    if (password !== confirmation) { setMessage("Passwords do not match."); return; }
    setBusy(true);
    try {
      const response = await fetch("/api/auth/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ fullName, email, password }),
      });
      const result = await response.json() as { message?: string; error?: string };
      if (!response.ok) throw new Error(result.error || "Registration could not be completed.");
      setAccepted(true);
      setMessage(result.message || "Check your email for a verification link.");
      setPassword("");
      setConfirmation("");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Registration is temporarily unavailable.");
    } finally { setBusy(false); }
  }

  return (
    <main style={{ minHeight: "100vh", display: "grid", placeItems: "center", background: "#f4f6f8", padding: 20, color: "#172432" }}>
      <section style={{ width: "min(100%, 460px)", background: "#fff", padding: 32, borderRadius: 14, border: "1px solid #e1e6eb", boxShadow: "0 12px 40px rgba(20,40,60,.08)" }}>
        <Link href="/" style={{ color: "#173f58", fontWeight: 800, textDecoration: "none", letterSpacing: 1 }}>MUCH MORE ELECTRONICS</Link>
        <p style={{ marginTop: 30, color: "#607180", fontSize: 12, letterSpacing: 1.5, fontWeight: 700 }}>CUSTOMER ACCOUNT</p>
        <h1 style={{ fontSize: 30, margin: "8px 0" }}>Create your account.</h1>
        <p style={{ color: "#607180", lineHeight: 1.5 }}>Register with your email. You must verify your email before MME can review customer account access.</p>
        <form onSubmit={submit} style={{ display: "grid", gap: 13, marginTop: 22 }}>
          <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Full name
            <input required autoComplete="name" maxLength={120} value={fullName} onChange={e => setFullName(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
          </label>
          <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Email
            <input required type="email" autoComplete="email" maxLength={320} value={email} onChange={e => setEmail(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
          </label>
          <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Password
            <input required type="password" autoComplete="new-password" minLength={12} maxLength={128} value={password} onChange={e => setPassword(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
            <span style={{ color: "#607180", fontWeight: 400 }}>Use at least 12 characters.</span>
          </label>
          <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Confirm password
            <input required type="password" autoComplete="new-password" minLength={12} maxLength={128} value={confirmation} onChange={e => setConfirmation(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
          </label>
          <button disabled={busy || accepted} type="submit" style={{ padding: 14, background: "#173f58", color: "#fff", border: 0, borderRadius: 8, fontWeight: 700, cursor: busy ? "wait" : "pointer" }}>{busy ? "Creating account…" : accepted ? "Registration submitted" : "Create account"}</button>
        </form>
        {message && <p role="status" aria-live="polite" style={{ marginTop: 18, padding: 12, background: "#f3f6f8", borderRadius: 8, lineHeight: 1.5 }}>{message}</p>}
        <p style={{ marginTop: 22, fontSize: 13 }}><Link href="/account" style={{ color: "#1b7181" }}>Already have an account? Sign in</Link></p>
      </section>
    </main>
  );
}
