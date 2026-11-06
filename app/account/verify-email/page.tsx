"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

export default function VerifyEmailPage() {
  const [tokenHash, setTokenHash] = useState("");
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [verified, setVerified] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const hash = params.get("token_hash") || "";
    const type = params.get("type") || "";
    if (type !== "email" || hash.length < 20 || hash.length > 512 || !/^[A-Za-z0-9_-]+$/.test(hash)) {
      setMessage("This verification link is invalid or incomplete. Request a new registration email.");
    } else {
      setTokenHash(hash);
      setReady(true);
    }
  }, []);

  async function verify() {
    if (!tokenHash || busy || verified) return;
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch("/api/auth/verify-email", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ tokenHash, type: "email" }),
      });
      const result = await response.json() as { verified?: boolean; message?: string; error?: string };
      if (!response.ok || !result.verified) throw new Error(result.error || "Email verification could not be completed.");
      setVerified(true);
      setTokenHash("");
      window.history.replaceState({}, "", "/account/verify-email?verified=1");
      setMessage(result.message || "Email verified. You can now sign in.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Email verification is temporarily unavailable.");
    } finally { setBusy(false); }
  }

  return (
    <main style={{ minHeight: "100vh", display: "grid", placeItems: "center", background: "#f4f6f8", padding: 20, color: "#172432" }}>
      <section style={{ width: "min(100%, 460px)", background: "#fff", padding: 32, borderRadius: 14, border: "1px solid #e1e6eb", boxShadow: "0 12px 40px rgba(20,40,60,.08)" }}>
        <Link href="/" style={{ color: "#173f58", fontWeight: 800, textDecoration: "none", letterSpacing: 1 }}>MUCH MORE ELECTRONICS</Link>
        <p style={{ marginTop: 30, color: "#607180", fontSize: 12, letterSpacing: 1.5, fontWeight: 700 }}>EMAIL VERIFICATION</p>
        <h1 style={{ fontSize: 30, margin: "8px 0" }}>{verified ? "Email verified." : "Confirm your email."}</h1>
        <p style={{ color: "#607180", lineHeight: 1.5 }}>For your security, opening this page does not consume the one-time link. Select the button below to complete verification.</p>
        {ready && !verified && <button type="button" disabled={busy} onClick={verify} style={{ width: "100%", marginTop: 20, padding: 14, background: "#173f58", color: "#fff", border: 0, borderRadius: 8, fontWeight: 700, cursor: busy ? "wait" : "pointer" }}>{busy ? "Verifying…" : "Verify email address"}</button>}
        {message && <p role="status" aria-live="polite" style={{ marginTop: 18, padding: 12, background: "#f3f6f8", borderRadius: 8, lineHeight: 1.5 }}>{message}</p>}
        {verified && <Link href="/account" style={{ display: "block", marginTop: 20, padding: 14, textAlign: "center", background: "#173f58", color: "#fff", borderRadius: 8, fontWeight: 700, textDecoration: "none" }}>Continue to sign in</Link>}
        {!verified && <p style={{ marginTop: 22, fontSize: 13 }}><Link href="/account/register" style={{ color: "#1b7181" }}>Return to registration</Link></p>}
      </section>
    </main>
  );
}
