"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";

type Mode = "signin" | "register";

export default function AccountPage() {
  const [mode, setMode] = useState<Mode>("signin");
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
      const response = await fetch(mode === "register" ? "/api/auth/customer-sign-up" : "/api/auth/customer-sign-in", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        cache: "no-store",
        body: JSON.stringify({ email, password }),
      });
      const result = await response.json() as { error?: string; message?: string; authenticated?: boolean };
      if (mode === "register") {
        if (!response.ok && response.status !== 202) throw new Error(result.error || "Registration could not be submitted.");
        setMessage(result.message || "Check your email for a confirmation link. After confirming, return here to sign in.");
        setPassword("");
      } else {
        if (!response.ok || !result.authenticated) throw new Error(result.error || "Customer sign-in failed.");
        setSignedIn(true);
        setPassword("");
        setMessage("Your active MME customer access has been verified.");
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
    <main className="simple-page">
      <header className="header">
        <Link className="brand" href="/"><span className="brand-mark">MM</span><span>MUCH MORE<br /><b>ELECTRONICS</b></span></Link>
        <nav><Link href="/products">Shop all</Link></nav>
        <div className="actions"><Link href="/cart">Bag <span className="count">0</span></Link></div>
      </header>
      <section className="simple-content" style={{ width: "min(100%, 620px)", margin: "0 auto" }}>
        <div className="eyebrow">Your MME</div>
        <h1>Customer <em>account.</em></h1>
        <p>Sign in to your MME customer account or create one to get started. Email confirmation is required before customer access can be activated.</p>
        {!signedIn ? <>
          <div role="group" aria-label="Account action" style={{ display: "flex", gap: 10, margin: "28px 0 20px" }}>
            <button type="button" onClick={() => { setMode("signin"); setMessage(""); }} aria-pressed={mode === "signin"} style={{ padding: "11px 18px", border: "1px solid #164b3c", background: mode === "signin" ? "#164b3c" : "transparent", color: mode === "signin" ? "white" : "#164b3c", borderRadius: 3, cursor: "pointer" }}>Sign in</button>
            <button type="button" onClick={() => { setMode("register"); setMessage(""); }} aria-pressed={mode === "register"} style={{ padding: "11px 18px", border: "1px solid #164b3c", background: mode === "register" ? "#164b3c" : "transparent", color: mode === "register" ? "white" : "#164b3c", borderRadius: 3, cursor: "pointer" }}>Create account</button>
          </div>
          <form onSubmit={submit} style={{ display: "grid", gap: 14, maxWidth: 440 }}>
            <label style={{ display: "grid", gap: 7, fontSize: 12, fontWeight: 600 }}>Email address
              <input type="email" autoComplete="email" required maxLength={320} value={email} onChange={event => setEmail(event.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 4, background: "white" }} />
            </label>
            <label style={{ display: "grid", gap: 7, fontSize: 12, fontWeight: 600 }}>Password
              <input type="password" autoComplete={mode === "register" ? "new-password" : "current-password"} required minLength={mode === "register" ? 10 : 1} maxLength={1024} value={password} onChange={event => setPassword(event.target.value)} style={{ padding: 13, border: "1px solid #cbd4dc", borderRadius: 4, background: "white" }} />
            </label>
            {mode === "register" && <small style={{ color: "#6b7470", lineHeight: 1.6 }}>Use at least 10 characters. We will email a confirmation link to verify your address.</small>}
            <button className="button" type="submit" disabled={busy} style={{ border: 0, cursor: busy ? "wait" : "pointer" }}>{busy ? "Please wait…" : mode === "register" ? "Create customer account" : "Sign in securely"}</button>
          </form>
        </> : <button className="button" type="button" disabled={busy} onClick={signOut}>Sign out</button>}
        {message && <p role="status" aria-live="polite" style={{ marginTop: 20, padding: 14, background: "#f0eee7", borderRadius: 4, fontSize: 12 }}>{message}</p>}
        <p style={{ marginTop: 28, fontSize: 12 }}><Link href="/employee-sign-in" style={{ color: "#1b7181" }}>Employee sign-in</Link> · <Link href="/" style={{ color: "#1b7181" }}>Back to store</Link></p>
      </section>
      <footer className="simple-footer">© {new Date().getFullYear()} Much More Electronics <Link href="/">Home</Link></footer>
    </main>
  );
}
