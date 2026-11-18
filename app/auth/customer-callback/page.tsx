"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

export default function CustomerConfirmationPage() {
  const [message, setMessage] = useState("Verifying your email confirmation…");
  const [busy, setBusy] = useState(true);
  const router = useRouter();

  useEffect(() => {
    let cancelled = false;
    async function verify() {
      try {
        const fragment = new URLSearchParams(window.location.hash.replace(/^#/, ""));
        const error = fragment.get("error_description") || fragment.get("error");
        const accessToken = fragment.get("access_token");
        const refreshToken = fragment.get("refresh_token");
        const type = fragment.get("type");
        if (error) throw new Error("The confirmation link is invalid or expired. Request a new confirmation email.");
        if (!accessToken || !refreshToken || (type && type !== "signup" && type !== "email")) {
          throw new Error("The confirmation link is incomplete or expired. Please sign in or request a new link.");
        }
        const response = await fetch("/api/auth/customer-session", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          credentials: "same-origin",
          cache: "no-store",
          body: JSON.stringify({ access_token: accessToken, refresh_token: refreshToken }),
        });
        const result = await response.json() as { error?: string; message?: string; customerStatus?: string };
        if (!response.ok) throw new Error(result.error || "Email confirmation could not be verified.");
        if (!cancelled) {
          window.history.replaceState({}, document.title, window.location.pathname);
          setMessage(result.message || "Email confirmed.");
          if (result.customerStatus === "active") router.replace("/account");
        }
      } catch (error) {
        if (!cancelled) setMessage(error instanceof Error ? error.message : "Email confirmation could not be completed.");
      } finally {
        if (!cancelled) setBusy(false);
      }
    }
    void verify();
    return () => { cancelled = true; };
  }, [router]);

  return (
    <main className="simple-page">
      <section className="simple-content" style={{ width: "min(100%, 620px)", margin: "0 auto" }}>
        <div className="eyebrow">MME customer account</div>
        <h1>Email <em>confirmation.</em></h1>
        <p role="status" aria-live="polite">{message}</p>
        {busy && <p>One moment, please.</p>}
        {!busy && <p><Link href="/account" style={{ color: "#1b7181" }}>Continue to customer sign-in</Link></p>}
      </section>
    </main>
  );
}
