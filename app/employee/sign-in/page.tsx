"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";

export default function EmployeeSignInPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

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
      const access = await fetch("/api/auth/employee", { credentials: "same-origin", cache: "no-store" });
      const accessResult = await access.json() as { error?: string; authorized?: boolean };
      if (!access.ok) throw new Error(accessResult.error || "Employee access is not active for this login.");
      setMessage("Employee identity verified. Employee dashboard routing is the next integration step.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to verify employee access.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main style={{ minHeight: "100vh", display: "grid", placeItems: "center", background: "#edf2f5", padding: 20, color: "#172432" }}>
      <section style={{ width: "min(100%, 440px)", background: "#fff", padding: 32, borderRadius: 14, border: "1px solid #dce4e9" }}>
        <Link href="/" style={{ color: "#173f58", fontWeight: 800, textDecoration: "none", letterSpacing: 1 }}>MME · EMPLOYEE ACCESS</Link>
        <p style={{ marginTop: 30, color: "#607180", fontSize: 12, letterSpacing: 1.5, fontWeight: 700 }}>SECURE STAFF SIGN-IN</p>
        <h1 style={{ fontSize: 32, margin: "8px 0" }}>Employee portal.</h1>
        <p style={{ color: "#607180", lineHeight: 1.5 }}>Sign in with your assigned MME account. Employee access is separately checked against your active employee identity.</p>
        <form onSubmit={submit} style={{ display: "grid", gap: 14, marginTop: 24 }}>
          <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Work email
            <input type="email" autoComplete="username" required maxLength={320} value={email} onChange={e => setEmail(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
          </label>
          <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Password
            <input type="password" autoComplete="current-password" required maxLength={1024} value={password} onChange={e => setPassword(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
          </label>
          <button disabled={busy} type="submit" style={{ padding: 14, background: "#173f58", color: "#fff", border: 0, borderRadius: 8, fontWeight: 700, cursor: busy ? "wait" : "pointer" }}>{busy ? "Verifying…" : "Sign in securely"}</button>
        </form>
        {message && <p role="status" aria-live="polite" style={{ marginTop: 18, padding: 12, background: "#f3f6f8", borderRadius: 8, lineHeight: 1.5 }}>{message}</p>}
        <p style={{ marginTop: 24, fontSize: 13 }}><Link href="/account" style={{ color: "#1b7181" }}>Customer sign-in</Link></p>
      </section>
    </main>
  );
}
