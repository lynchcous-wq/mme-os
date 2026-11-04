"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { getSupabaseBrowserClient } from "@/lib/supabase/browser";

export default function WorkflowCancellationPage() {
  const [email, setEmail] = useState("");
  const [executionId, setExecutionId] = useState("");
  const [reason, setReason] = useState("");
  const [confirm, setConfirm] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    void supabase.auth.getSession().then(({ data }) => setEmail(data.session?.user.email ?? ""));
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setEmail(session?.user.email ?? "");
      setConfirm(false);
      setMessage("");
    });
    return () => data.subscription.unsubscribe();
  }, []);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setMessage("");
    if (!email) {
      setError("Sign in with your employee account before requesting cancellation.");
      return;
    }
    if (!confirm) {
      setError("Review the warning and confirm that you want to cancel this workflow.");
      return;
    }
    setSubmitting(true);
    try {
      const { data, error: sessionError } = await getSupabaseBrowserClient().auth.getSession();
      const token = data.session?.access_token;
      if (sessionError || !token) throw new Error("Your employee session has expired. Sign in again.");
      const response = await fetch("/api/employee/workflows/cancellation", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer " + token },
        body: JSON.stringify({ execution_id: executionId.trim(), reason: reason.trim() }),
        cache: "no-store",
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error ?? "Workflow cancellation was rejected.");
      if (result.execution_status !== "cancelled") throw new Error("The cancellation response could not be verified.");
      setMessage("Cancellation recorded. In-flight steps, if any, have been routed for reconciliation.");
      setExecutionId("");
      setReason("");
      setConfirm(false);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Workflow cancellation could not be completed.");
    } finally {
      setSubmitting(false);
    }
  }

  const field: React.CSSProperties = {
    display: "block", width: "100%", boxSizing: "border-box", marginTop: 7,
    padding: 12, border: "1px solid #cbd5e1", borderRadius: 8, font: "inherit",
  };
  const panel: React.CSSProperties = {
    background: "white", border: "1px solid #e1e7ef", borderRadius: 14,
    padding: 22, marginTop: 20,
  };

  return (
    <main style={{ minHeight: "100vh", background: "#f4f6fa", color: "#172033" }}>
      <header style={{ background: "#101b32", color: "white", padding: "17px 5vw" }}>
        <Link href="/" style={{ color: "white", textDecoration: "none", fontWeight: 800 }}>MME · EMPLOYEE OPERATIONS</Link>
      </header>
      <section style={{ maxWidth: 760, margin: "0 auto", padding: "38px 20px 80px" }}>
        <p style={{ color: "#526b91", fontSize: 12, fontWeight: 800, letterSpacing: ".14em" }}>BUILD 006 / WORKFLOW GOVERNANCE</p>
        <h1 style={{ fontSize: "clamp(30px,5vw,44px)", margin: "8px 0" }}>Supervisor workflow cancellation</h1>
        <p style={{ color: "#586579", lineHeight: 1.6 }}>
          Request cancellation of a workflow execution. The server validates your employee identity and supervisor permissions. Enter the execution ID from the workflow record; browser-supplied actor IDs are not accepted.
        </p>

        <section style={panel}>
          <b>Employee session</b>
          <p style={{ color: "#586579", marginBottom: 0 }}>{email || "Not signed in"}</p>
          {!email && <p style={{ color: "#8a4b10" }}>Sign in through the MME employee portal before submitting.</p>}
        </section>

        <form onSubmit={submit} style={panel}>
          <label style={{ display: "block", fontWeight: 700 }}>
            Workflow execution UUID
            <input required value={executionId} onChange={event => { setExecutionId(event.target.value); setConfirm(false); }}
              placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" style={field} />
          </label>
          <label style={{ display: "block", fontWeight: 700, marginTop: 16 }}>
            Cancellation reason
            <textarea required minLength={3} maxLength={1000} rows={4} value={reason}
              onChange={event => { setReason(event.target.value); setConfirm(false); }}
              placeholder="Explain why this workflow must be stopped and what operational checks were completed."
              style={field} />
          </label>

          <div style={{ background: "#fff7e8", border: "1px solid #f0d7a8", borderRadius: 10, padding: 14, marginTop: 18 }}>
            <b>Important operational warning</b>
            <p style={{ marginBottom: 0, lineHeight: 1.55 }}>
              Cancellation stops queued work and invalidates active leases. A running step may already have triggered an external side effect. Such steps are sent to manual reconciliation; cancellation does not reverse payments, messages, shipments, or other external actions.
            </p>
          </div>

          <label style={{ display: "flex", alignItems: "flex-start", gap: 10, marginTop: 18, lineHeight: 1.45 }}>
            <input type="checkbox" checked={confirm} onChange={event => setConfirm(event.target.checked)} style={{ marginTop: 4 }} />
            I verified the execution ID, reviewed the reason, and understand the side-effect warning.
          </label>

          {message && <p role="status" style={{ color: "#205b37", background: "#eef8f0", padding: 12, borderRadius: 8 }}>{message}</p>}
          {error && <p role="alert" style={{ color: "#8b2424", background: "#fff0f0", padding: 12, borderRadius: 8 }}>{error}</p>}

          <button type="submit" disabled={!email || !confirm || submitting || executionId.trim().length === 0 || reason.trim().length < 3}
            style={{ width: "100%", marginTop: 18, border: 0, borderRadius: 8, padding: 13, background: "#8b2424", color: "white", fontWeight: 800, cursor: "pointer", opacity: !email || !confirm || submitting ? .55 : 1 }}>
            {submitting ? "Submitting cancellation…" : "Confirm workflow cancellation"}
          </button>
        </form>

        <p style={{ marginTop: 18 }}>
          <Link href="/employee/workflows/reconciliation">Open cancelled-workflow reconciliation ↗</Link>
          {" · "}
          <Link href="/employee/workflows/recovery">Open recovery review ↗</Link>
        </p>
      </section>
    </main>
  );
}
