"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { getSupabaseBrowserClient } from "@/lib/supabase/browser";

type RecoveryReview = {
  step_run_id: number;
  execution_id: string;
  workflow_key: string;
  workflow_name: string;
  workflow_version: number;
  department: string;
  step_key: string;
  step_type: string;
  attempt_count: number;
  max_attempts: number;
  recovery_reason: string | null;
  recovery_policy: string;
  compensation_status: string;
  idempotency_key: string;
  last_error_code: string | null;
  last_error_summary: string | null;
  correlation_id: string | null;
  execution_created_at: string;
  audit_history: Array<{
    event_type: string;
    actor: string;
    event_data: Record<string, unknown>;
    created_at: string;
  }>;
};

type Decision = "confirmed_succeeded" | "safe_to_retry" | "abandoned";
type Draft = { resolution: Decision | ""; reason: string; evidence: string };

const initialDraft: Draft = { resolution: "", reason: "", evidence: "{}" };

export default function WorkflowRecoveryPage() {
  const [email, setEmail] = useState("");
  const [authMessage, setAuthMessage] = useState("");
  const [reviews, setReviews] = useState<RecoveryReview[]>([]);
  const [drafts, setDrafts] = useState<Record<number, Draft>>({});
  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState<number | null>(null);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [emailInput, setEmailInput] = useState("");
  const [password, setPassword] = useState("");

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    void supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (sessionError) setAuthMessage(sessionError.message);
      setEmail(data.session?.user.email ?? "");
    });
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setEmail(session?.user.email ?? "");
      setReviews([]);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const loadReviews = useCallback(async () => {
    setLoading(true);
    setError("");
    setMessage("");
    try {
      const { data, error: sessionError } = await getSupabaseBrowserClient().auth.getSession();
      const token = data.session?.access_token;
      if (sessionError || !token) throw new Error("Sign in with your employee account to view recovery reviews.");
      const response = await fetch("/api/employee/workflows/recovery?limit=100", {
        headers: { Authorization: "Bearer " + token },
        cache: "no-store",
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error ?? "Recovery inbox could not be loaded.");
      const rows = Array.isArray(result.reviews) ? result.reviews as RecoveryReview[] : [];
      setReviews(rows);
      setDrafts(current => {
        const next = { ...current };
        for (const row of rows) if (!next[row.step_run_id]) next[row.step_run_id] = { ...initialDraft };
        return next;
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Recovery inbox unavailable.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (email) void loadReviews();
  }, [email, loadReviews]);

  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setAuthMessage("");
    try {
      const { error: signInError } = await getSupabaseBrowserClient().auth.signInWithPassword({
        email: emailInput.trim(), password,
      });
      if (signInError) throw signInError;
      setPassword("");
    } catch (cause) {
      setAuthMessage(cause instanceof Error ? cause.message : "Employee sign-in failed.");
    }
  }

  async function signOut() {
    const { error: signOutError } = await getSupabaseBrowserClient().auth.signOut();
    if (signOutError) setAuthMessage(signOutError.message);
    else {
      setReviews([]);
      setMessage("Signed out.");
    }
  }

  function updateDraft(id: number, patch: Partial<Draft>) {
    setDrafts(current => ({ ...current, [id]: { ...(current[id] ?? initialDraft), ...patch } }));
  }

  async function submitDecision(event: React.FormEvent<HTMLFormElement>, review: RecoveryReview) {
    event.preventDefault();
    const draft = drafts[review.step_run_id] ?? initialDraft;
    setSubmitting(review.step_run_id);
    setError("");
    setMessage("");
    try {
      const { data, error: sessionError } = await getSupabaseBrowserClient().auth.getSession();
      const token = data.session?.access_token;
      if (sessionError || !token) throw new Error("Your employee session has expired. Sign in again.");
      if (!draft.resolution) throw new Error("Choose a recovery decision before submitting.");
      if (draft.reason.trim().length < 3) throw new Error("Enter a review reason of at least 3 characters.");
      let evidence: unknown;
      try {
        evidence = JSON.parse(draft.evidence || "{}");
      } catch {
        throw new Error("Evidence must be valid JSON.");
      }
      if (!evidence || typeof evidence !== "object" || Array.isArray(evidence)) {
        throw new Error("Evidence must be a JSON object.");
      }
      if (draft.resolution !== "abandoned" && Object.keys(evidence as Record<string, unknown>).length === 0) {
        throw new Error("Non-empty evidence is required to confirm success or authorize a retry.");
      }
      const response = await fetch("/api/employee/workflows/recovery", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer " + token },
        body: JSON.stringify({
          step_run_id: review.step_run_id,
          resolution: draft.resolution,
          reason: draft.reason.trim(),
          evidence,
        }),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error ?? "Recovery decision was rejected.");
      setMessage("Decision recorded. Workflow status: " + result.execution_status + ".");
      await loadReviews();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not submit recovery decision.");
    } finally {
      setSubmitting(null);
    }
  }

  const panel: React.CSSProperties = {
    background: "white", border: "1px solid #e1e7ef", borderRadius: 14,
    padding: 22, marginBottom: 16, boxShadow: "0 4px 18px rgba(16,27,50,.04)",
  };
  const field: React.CSSProperties = {
    width: "100%", boxSizing: "border-box", padding: 11, border: "1px solid #cbd5e1",
    borderRadius: 8, font: "inherit", marginTop: 6,
  };
  const primary: React.CSSProperties = {
    border: 0, borderRadius: 8, padding: "11px 16px", background: "#173b70",
    color: "white", fontWeight: 700, cursor: "pointer",
  };

  return (
    <main style={{ minHeight: "100vh", background: "#f4f6fa", color: "#172033" }}>
      <header style={{ background: "#101b32", color: "white", padding: "17px 5vw", display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16 }}>
        <Link href="/" style={{ color: "white", textDecoration: "none", fontWeight: 800, letterSpacing: ".06em" }}>MME · EMPLOYEE OPERATIONS</Link>
        <Link href="/employee/inventory/inspection" style={{ color: "#dce6f7" }}>Inspection station ↗</Link>
      </header>
      <section style={{ maxWidth: 1040, margin: "0 auto", padding: "38px 20px 80px" }}>
        <p style={{ color: "#526b91", fontSize: 12, fontWeight: 800, letterSpacing: ".14em" }}>BUILD 006 / WORKFLOW GOVERNANCE</p>
        <h1 style={{ fontSize: "clamp(30px,5vw,44px)", margin: "8px 0" }}>Workflow recovery review</h1>
        <p style={{ color: "#586579", lineHeight: 1.6, maxWidth: 760 }}>
          Review interrupted workflow steps before they are resumed. Confirm success only when evidence establishes the external action completed. Authorize a retry only after verifying replay is safe.
        </p>

        <section style={panel}>
          <h2 style={{ marginTop: 0 }}>Employee access</h2>
          {email ? (
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 12 }}>
              <span>Signed in as <b>{email}</b></span>
              <button type="button" onClick={signOut} style={{ ...primary, background: "#e8edf5", color: "#172033" }}>Sign out</button>
            </div>
          ) : (
            <form onSubmit={signIn} style={{ display: "grid", gap: 10, maxWidth: 420 }}>
              <input required type="email" autoComplete="username" value={emailInput} onChange={event => setEmailInput(event.target.value)} placeholder="Employee email" style={field} />
              <input required type="password" autoComplete="current-password" value={password} onChange={event => setPassword(event.target.value)} placeholder="Password" style={field} />
              <button type="submit" style={primary}>Sign in</button>
            </form>
          )}
          {authMessage && <p role="status">{authMessage}</p>}
        </section>

        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap", margin: "24px 0 14px" }}>
          <div><h2 style={{ margin: 0 }}>Awaiting review</h2><p style={{ color: "#586579", margin: "5px 0 0" }}>{reviews.length} item(s) returned by your authorized inbox</p></div>
          <button type="button" onClick={() => void loadReviews()} disabled={!email || loading} style={primary}>{loading ? "Refreshing…" : "Refresh inbox"}</button>
        </div>

        {message && <p role="status" style={{ ...panel, borderColor: "#b7d8c2", color: "#205b37" }}>{message}</p>}
        {error && <p role="alert" style={{ ...panel, borderColor: "#e7b8b8", color: "#8b2424" }}>{error}</p>}
        {!email && <p style={{ color: "#586579" }}>Sign in to load recovery reviews.</p>}
        {email && !loading && reviews.length === 0 && !error && <section style={panel}><b>No paused workflows are awaiting your review.</b><p style={{ color: "#586579", marginBottom: 0 }}>Your inbox is limited by your workflow-review permissions.</p></section>}

        {reviews.map(review => {
          const draft = drafts[review.step_run_id] ?? initialDraft;
          return (
            <article key={review.step_run_id} style={panel}>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                <div>
                  <p style={{ margin: "0 0 5px", color: "#526b91", fontSize: 12, fontWeight: 800 }}>{review.department} · {review.workflow_key} · v{review.workflow_version}</p>
                  <h3 style={{ margin: 0, fontSize: 21 }}>{review.workflow_name}</h3>
                  <p style={{ color: "#586579", margin: "6px 0" }}>Step: <b>{review.step_key}</b> ({review.step_type})</p>
                </div>
                <span style={{ alignSelf: "start", borderRadius: 20, background: "#fff1d8", color: "#79520b", padding: "6px 11px", fontSize: 12, fontWeight: 800 }}>MANUAL REVIEW</span>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(150px,1fr))", gap: 10, margin: "16px 0" }}>
                <div><small style={{ color: "#667085" }}>Attempts</small><div>{review.attempt_count} / {review.max_attempts}</div></div>
                <div><small style={{ color: "#667085" }}>Recovery policy</small><div>{review.recovery_policy}</div></div>
                <div><small style={{ color: "#667085" }}>Compensation</small><div>{review.compensation_status}</div></div>
                <div><small style={{ color: "#667085" }}>Execution ID</small><div style={{ overflowWrap: "anywhere", fontSize: 12 }}>{review.execution_id}</div></div>
              </div>
              {review.last_error_summary && <p style={{ background: "#f7f8fa", padding: 12, borderRadius: 8 }}>{review.last_error_summary}</p>}
              {review.recovery_reason && <p><b>Recovery reason:</b> {review.recovery_reason}</p>}
              {review.idempotency_key && <p style={{ fontSize: 12, color: "#586579", overflowWrap: "anywhere" }}>Idempotency key: {review.idempotency_key}</p>}
              <details style={{ margin: "14px 0" }}>
                <summary style={{ cursor: "pointer", fontWeight: 700 }}>Audit history ({review.audit_history?.length ?? 0})</summary>
                <div style={{ display: "grid", gap: 8, marginTop: 10 }}>
                  {(review.audit_history ?? []).map((entry, index) => (
                    <div key={entry.created_at + index} style={{ background: "#f7f8fa", padding: 10, borderRadius: 8 }}>
                      <b>{entry.event_type}</b><div style={{ color: "#586579", fontSize: 12 }}>{entry.actor} · {entry.created_at}</div>
                      <pre style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontSize: 11 }}>{JSON.stringify(entry.event_data, null, 2)}</pre>
                    </div>
                  ))}
                </div>
              </details>
              <form onSubmit={event => void submitDecision(event, review)} style={{ borderTop: "1px solid #e5eaf1", paddingTop: 16, display: "grid", gap: 12 }}>
                <label>Decision
                  <select required value={draft.resolution} onChange={event => updateDraft(review.step_run_id, { resolution: event.target.value as Decision | "" })} style={field}>
                    <option value="" disabled>Choose a decision…</option>
                    <option value="confirmed_succeeded">Confirm step succeeded (evidence required)</option>
                    <option value="safe_to_retry">Authorize safe retry</option>
                    <option value="abandoned">Abandon workflow step</option>
                  </select>
                </label>
                <label>Reason (required)
                  <textarea required minLength={3} maxLength={1000} value={draft.reason} onChange={event => updateDraft(review.step_run_id, { reason: event.target.value })} rows={3} style={field} placeholder="Document what was checked and why this decision is safe." />
                </label>
                <label>Evidence JSON
                  <textarea value={draft.evidence} onChange={event => updateDraft(review.step_run_id, { evidence: event.target.value })} rows={3} style={{ ...field, fontFamily: "monospace", fontSize: 12 }} />
                </label>
                <p style={{ margin: 0, color: "#79520b", fontSize: 12 }}>This decision is audited and cannot be treated as a reversible draft. Confirm the step's external side effects before submitting.</p>
                <button type="submit" disabled={submitting === review.step_run_id} style={primary}>{submitting === review.step_run_id ? "Submitting…" : "Submit recovery decision"}</button>
              </form>
            </article>
          );
        })}
      </section>
    </main>
  );
}
