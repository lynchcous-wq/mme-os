"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";

export default function CustomerLinkRequestPage() {
  const [customerReference, setCustomerReference] = useState("");
  const [phoneLast4, setPhoneLast4] = useState("");
  const [note, setNote] = useState("");
  const [message, setMessage] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true); setMessage("");
    try {
      const response = await fetch("/api/auth/customer/link-request", {
        method: "POST", headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ customerReference, phoneLast4, note }),
      });
      const result = await response.json() as { message?: string; error?: string };
      if (!response.ok) throw new Error(result.error || "Request could not be submitted.");
      setSubmitted(true); setMessage(result.message || "Your request was submitted for review.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Request could not be submitted.");
    } finally { setBusy(false); }
  }

  return <main style={{ minHeight: "100vh", display: "grid", placeItems: "center", background: "#f4f6f8", padding: 20, color: "#172432" }}>
    <section style={{ width: "min(100%, 480px)", background: "#fff", padding: 32, borderRadius: 14, border: "1px solid #e1e6eb" }}>
      <Link href="/" style={{ color: "#173f58", fontWeight: 800, textDecoration: "none" }}>MUCH MORE ELECTRONICS</Link>
      <p style={{ marginTop: 30, color: "#607180", fontSize: 12, letterSpacing: 1.5, fontWeight: 700 }}>CUSTOMER IDENTITY REVIEW</p>
      <h1 style={{ fontSize: 28, margin: "8px 0" }}>Connect your MME account.</h1>
      <p style={{ color: "#607180", lineHeight: 1.5 }}>Sign in with your verified email, then provide an optional customer or order reference to help our team locate your existing profile. Do not submit passwords, full payment-card details, or government ID numbers.</p>
      <form onSubmit={submit} style={{ display: "grid", gap: 14, marginTop: 22 }}>
        <label style={{ display: "grid", gap: 6, fontSize: 13, fontWeight: 600 }}>Customer or order reference (optional)
          <input maxLength={80} value={customerReference} onChange={e=>setCustomerReference(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
        </label>
        <label style={{ display: "grid", gap: 6, fontSize: 13, fontWeight: 600 }}>Last four digits of phone on file (optional)
          <input inputMode="numeric" maxLength={4} pattern="[0-9]{4}" value={phoneLast4} onChange={e=>setPhoneLast4(e.target.value.replace(/\D/g,"").slice(0,4))} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 16 }} />
        </label>
        <label style={{ display: "grid", gap: 6, fontSize: 13, fontWeight: 600 }}>Additional information (optional)
          <textarea maxLength={1000} rows={4} value={note} onChange={e=>setNote(e.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 8, fontSize: 15 }} />
        </label>
        <button disabled={busy || submitted} type="submit" style={{ padding: 14, background: "#173f58", color: "#fff", border: 0, borderRadius: 8, fontWeight: 700 }}>{busy ? "Submitting…" : submitted ? "Request submitted" : "Submit for identity review"}</button>
      </form>
      {message && <p role="status" aria-live="polite" style={{ marginTop: 18, padding: 12, background: "#f3f6f8", borderRadius: 8, lineHeight: 1.5 }}>{message}</p>}
      <p style={{ marginTop: 20, fontSize: 13 }}><Link href="/account" style={{ color: "#1b7181" }}>Return to customer sign-in</Link></p>
    </section>
  </main>;
}
