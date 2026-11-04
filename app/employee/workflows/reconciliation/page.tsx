"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { getSupabaseBrowserClient } from "@/lib/supabase/browser";

type AuditEvent = {
  event_type: string;
  actor: string;
  event_data: Record<string, unknown>;
  created_at: string;
};

type ReconciliationItem = {
  step_run_id: number;
  execution_id: string;
  workflow_key: string;
  workflow_name: string;
  workflow_version: number;
  department: string;
  step_key: string;
  step_type: string;
  step_status: string;
  attempt_count: number;
  max_attempts: number;
  recovery_reason: string | null;
  recovery_policy: string;
  compensation_status: string;
  idempotency_key: string | null;
  last_error_code: string | null;
  last_error_summary: string | null;
  correlation_id: string | null;
  execution_created_at: string;
  audit_history: AuditEvent[];
};

export default function WorkflowReconciliationPage() {
  const [email, setEmail] = useState("");
  const [items, setItems] = useState<ReconciliationItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [authMessage, setAuthMessage] = useState("");

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    void supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (sessionError) setAuthMessage(sessionError.message);
      setEmail(data.session?.user.email ?? "");
    });
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setEmail(session?.user.email ?? "");
      setItems([]);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const { data, error: sessionError } = await getSupabaseBrowserClient().auth.getSession();
      const token = data.session?.access_token;
      if (sessionError || !token) throw new Error("Sign in with your employee account to view reconciliation items.");
      const response = await fetch("/api/employee/workflows/reconciliation?limit=100", {
        headers: { Authorization: "Bearer " + token },
        cache: "no-store",
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error ?? "Reconciliation inbox could not be loaded.");
      setItems(Array.isArray(result.items) ? result.items as ReconciliationItem[] : []);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Reconciliation inbox unavailable.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (email) void refresh();
  }, [email, refresh]);

  async function signOut() {
    const { error: signOutError } = await getSupabaseBrowserClient().auth.signOut();
    if (signOutError) setAuthMessage(signOutError.message);
    else {
      setItems([]);
      setAuthMessage("Signed out.");
    }
  }

  return (
    <main style={{ minHeight: "100vh", background: "#f4f6fa", color: "#172033" }}>
      <header style={{ background: "#101b32", color: "white", padding: "17px 5vw" }}>
        <Link href="/" style={{ color: "white", textDecoration: "none", fontWeight: 800 }}>
          MME · EMPLOYEE OPERATIONS
        </Link>
      </header>
      <section style={{ maxWidth: 1040, margin: "0 auto", padding: "36px 20px 80px" }}>
        <p style={{ color: "#526b91", fontSize: 12, fontWeight: 800, letterSpacing: ".14em" }}>
          BUILD 006 / WORKFLOW GOVERNANCE
        </p>
        <h1 style={{ fontSize: "clamp(30px,5vw,44px)", margin: "8px 0" }}>
          Cancelled workflow reconciliation
        </h1>
        <p style={{ color: "#586579", lineHeight: 1.6, maxWidth: 800 }}>
          Read-only review of steps that were running when a supervisor cancelled their workflow.
          External side effects may already have occurred. Review the audit trail before taking action elsewhere.
        </p>

        <section style={{ background: "white", border: "1px solid #e1e7ef", borderRadius: 14, padding: 20, margin: "22px 0" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
            <div>
              <b>{email || "Employee session required"}</b>
              <p style={{ color: "#667085", margin: "5px 0 0" }}>
                {items.length} authorized reconciliation item(s)
              </p>
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              {email && <button type="button" onClick={() => void signOut()} style={{ border: "1px solid #cbd5e1", borderRadius: 8, padding: "10px 14px", background: "white" }}>Sign out</button>}
              <button type="button" onClick={() => void refresh()} disabled={!email || loading}
                style={{ border: 0, borderRadius: 8, padding: "11px 16px", background: "#173b70", color: "white", fontWeight: 700 }}>
                {loading ? "Refreshing…" : "Refresh inbox"}
              </button>
            </div>
          </div>
        </section>

        {authMessage && <p role="status">{authMessage}</p>}
        {error && <p role="alert" style={{ background: "white", padding: 16, border: "1px solid #e7b8b8", borderRadius: 10, color: "#8b2424" }}>{error}</p>}
        {!email && <p>Sign in with your employee account to load this restricted inbox.</p>}
        {email && !loading && items.length === 0 && !error && (
          <p style={{ background: "white", padding: 18, borderRadius: 10 }}>
            No cancelled workflow steps currently require reconciliation within your authorized departments.
          </p>
        )}

        {items.map(item => (
          <article key={item.step_run_id} style={{ background: "white", border: "1px solid #e1e7ef", borderRadius: 14, padding: 20, marginBottom: 14 }}>
            <p style={{ margin: "0 0 6px", color: "#526b91", fontSize: 12, fontWeight: 800 }}>
              {item.department} · {item.workflow_key} · v{item.workflow_version}
            </p>
            <h2 style={{ margin: 0, fontSize: 21 }}>{item.workflow_name}</h2>
            <p>Step <b>{item.step_key}</b> ({item.step_type}) · Status: <b>{item.step_status}</b></p>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(160px,1fr))", gap: 12, margin: "16px 0" }}>
              <div><small>Attempts</small><div>{item.attempt_count} / {item.max_attempts}</div></div>
              <div><small>Compensation status</small><div>{item.compensation_status}</div></div>
              <div><small>Recovery policy</small><div>{item.recovery_policy}</div></div>
              <div><small>Step run ID</small><div>{item.step_run_id}</div></div>
            </div>
            {item.last_error_code && <p><b>Error code:</b> {item.last_error_code}</p>}
            {item.last_error_summary && <p style={{ background: "#f7f8fa", padding: 12, borderRadius: 8 }}>{item.last_error_summary}</p>}
            <p><b>Reconciliation reason:</b> {item.recovery_reason ?? "Not specified"}</p>
            <p style={{ fontSize: 12, overflowWrap: "anywhere" }}><b>Execution ID:</b> {item.execution_id}</p>
            {item.idempotency_key && <p style={{ fontSize: 12, overflowWrap: "anywhere" }}>Idempotency key: {item.idempotency_key}</p>}
            {item.correlation_id && <p style={{ fontSize: 12, overflowWrap: "anywhere" }}>Correlation ID: {item.correlation_id}</p>}
            <details style={{ marginTop: 14 }}>
              <summary style={{ cursor: "pointer", fontWeight: 700 }}>Audit history ({item.audit_history?.length ?? 0})</summary>
              {(item.audit_history ?? []).map((event, index) => (
                <div key={event.created_at + index} style={{ background: "#f7f8fa", padding: 10, borderRadius: 8, marginTop: 8 }}>
                  <b>{event.event_type}</b>
                  <div style={{ color: "#667085", fontSize: 12 }}>{event.actor} · {event.created_at}</div>
                  <pre style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontSize: 11 }}>
                    {JSON.stringify(event.event_data, null, 2)}
                  </pre>
                </div>
              ))}
            </details>
            <p style={{ color: "#8a4b10", background: "#fff7e8", padding: 12, borderRadius: 8, marginBottom: 0 }}>
              Investigation only. This screen cannot resume, retry, or mark the cancelled workflow successful.
            </p>
          </article>
        ))}
      </section>
    </main>
  );
}
