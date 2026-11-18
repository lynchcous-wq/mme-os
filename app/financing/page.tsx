"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";

type FormState = {
  fullName: string;
  email: string;
  phone: string;
  productInterest: string;
  estimatedBudget: string;
  preferredContact: string;
  consentToContact: boolean;
  website: string;
};

const initial: FormState = {
  fullName: "", email: "", phone: "", productInterest: "not_sure",
  estimatedBudget: "not_sure", preferredContact: "email",
  consentToContact: false, website: "",
};

export default function FinancingPage() {
  const [form, setForm] = useState<FormState>(initial);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [success, setSuccess] = useState(false);

  function update<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm(current => ({ ...current, [key]: value }));
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    setSuccess(false);
    try {
      const response = await fetch("/api/financing/inquiries", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        body: JSON.stringify(form),
      });
      const result = await response.json() as { message?: string; error?: string };
      if (!response.ok) throw new Error(result.error || "Your inquiry could not be submitted.");
      setSuccess(true);
      setMessage(result.message || "Your inquiry has been received.");
      setForm(initial);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Your inquiry could not be submitted.");
    } finally {
      setBusy(false);
    }
  }

  const fieldStyle = { padding: 13, border: "1px solid #cbd4dc", borderRadius: 4, background: "white", width: "100%", font: "inherit" };
  const labelStyle = { display: "grid", gap: 7, fontSize: 13, fontWeight: 600 as const };

  return (
    <main className="simple-page">
      <header className="header">
        <Link className="brand" href="/" aria-label="Much More Electronics home"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
        <nav aria-label="Main navigation"><Link href="/">Home</Link><Link href="/products">Shop all</Link><Link href="/account">Account</Link></nav>
        <div className="actions"><Link href="/cart">Shopping bag</Link></div>
      </header>

      <section className="simple-content" style={{ width: "min(100%, 760px)", margin: "0 auto" }}>
        <div className="eyebrow">MME financing information</div>
        <h1>Explore your <em>options.</em></h1>
        <p>Tell us what you are shopping for and how you would like to be contacted. This short inquiry helps our team understand what information you need before you visit a financing provider.</p>

        <div style={{ padding: 18, margin: "24px 0", border: "1px solid #d8e2dc", background: "#f4f7f3", borderRadius: 5 }}>
          <strong>This is an inquiry, not a credit application.</strong>
          <p style={{ margin: "8px 0 0", fontSize: 13, lineHeight: 1.6 }}>No credit check is performed and no financing decision is made here. Do not submit a Social Security number, date of birth, bank information, income, credit score, or identity documents. If you choose to apply, use the lender's official secure application.</p>
        </div>

        <form onSubmit={submit} style={{ display: "grid", gap: 16 }}>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(220px,1fr))", gap: 14 }}>
            <label style={labelStyle}>Full name<input style={fieldStyle} autoComplete="name" required minLength={2} maxLength={120} value={form.fullName} onChange={e => update("fullName", e.target.value)} /></label>
            <label style={labelStyle}>Email address<input style={fieldStyle} type="email" autoComplete="email" required maxLength={320} value={form.email} onChange={e => update("email", e.target.value)} /></label>
            <label style={labelStyle}>Phone number<input style={fieldStyle} type="tel" autoComplete="tel" required minLength={7} maxLength={32} value={form.phone} onChange={e => update("phone", e.target.value)} /></label>
            <label style={labelStyle}>What are you shopping for?
              <select style={fieldStyle} value={form.productInterest} onChange={e => update("productInterest", e.target.value)}>
                <option value="not_sure">Not sure yet</option><option value="television">Television</option><option value="computer">Computer / laptop</option><option value="phone_tablet">Phone / tablet</option><option value="wearable">Watch / wearable</option><option value="accessories">Accessories</option><option value="multiple">Multiple products</option>
              </select>
            </label>
            <label style={labelStyle}>Estimated purchase range
              <select style={fieldStyle} value={form.estimatedBudget} onChange={e => update("estimatedBudget", e.target.value)}>
                <option value="not_sure">Not sure</option><option value="under_250">Under $250</option><option value="250_499">$250–$499</option><option value="500_999">$500–$999</option><option value="1000_1999">$1,000–$1,999</option><option value="2000_plus">$2,000+</option>
              </select>
            </label>
            <label style={labelStyle}>Preferred contact method
              <select style={fieldStyle} value={form.preferredContact} onChange={e => update("preferredContact", e.target.value)}>
                <option value="email">Email</option><option value="phone">Phone</option><option value="either">Either</option>
              </select>
            </label>
          </div>

          <label aria-hidden="true" style={{ position: "absolute", left: "-10000px", width: 1, height: 1, overflow: "hidden" }}>
            Website<input tabIndex={-1} autoComplete="off" value={form.website} onChange={e => update("website", e.target.value)} />
          </label>

          <label style={{ display: "flex", alignItems: "flex-start", gap: 10, fontSize: 13, lineHeight: 1.6 }}>
            <input type="checkbox" required checked={form.consentToContact} onChange={e => update("consentToContact", e.target.checked)} style={{ marginTop: 4 }} />
            I agree that Much More Electronics may contact me about this financing inquiry using my selected contact method. This consent does not authorize a credit check or lender application.
          </label>

          <button className="button" type="submit" disabled={busy} style={{ border: 0, cursor: busy ? "wait" : "pointer", justifySelf: "start" }}>{busy ? "Submitting…" : "Submit financing inquiry"}</button>
        </form>

        {message && <p role="status" aria-live="polite" style={{ marginTop: 18, padding: 14, background: success ? "#eef5ef" : "#f3f1ec", borderRadius: 4, lineHeight: 1.6 }}>{message}</p>}

        <div style={{ borderTop: "1px solid #e5e5df", marginTop: 32, paddingTop: 22, fontSize: 13, lineHeight: 1.7 }}>
          <strong>What happens next?</strong>
          <ol><li>Your inquiry is securely submitted to MME.</li><li>An MME representative can follow up using your selected contact method.</li><li>If you want to apply, you will be directed to an available provider's official application. Provider terms, eligibility, rates and decisions are determined by that provider.</li></ol>
        </div>
        <p style={{ fontSize: 12 }}><Link href="/">Back to MME home</Link> · <Link href="/account">Customer account</Link></p>
      </section>

      <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/">Home</Link></footer>
    </main>
  );
}
