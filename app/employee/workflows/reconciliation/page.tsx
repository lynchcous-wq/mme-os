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

type DecisionDraft = { outcome: string; reason: string; evidenceJson: string };
type ReconciliationDecision = {
  id: number;
  outcome: string;
  reason: string;
  evidence_references: Array<{ kind: string; reference: string; sha256?: string }>;
  decided_by_user_id: string;
  decided_at: string;
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
  audit_history: AuditEvent[];\n  decision_history: ReconciliationDecision[];
};

export default function WorkflowReconciliationPage() {
  const [email, setEmail] = useState("");
  const [items, setItems] = useState<ReconciliationItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [authMessage, setAuthMessage] = useState("");
  const [drafts, setDrafts] = useState<Record<number, DecisionDraft>>({});
  const [submittingStep, setSubmittingStep] = useState<number | null>(null);
  const [decisionMessage, setDecisionMessage] = useState<Record<number, string>>({});

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

  function updateDraft(stepRunId: number, patch: Partial<DecisionDraft>) {
    setDrafts(current => ({
      ...current,
      [stepRunId]: {
        outcome: current[stepRunId]?.outcome ?? "confirmed_completed",
        reason: current[stepRunId]?.reason ?? "",
        evidenceJson: current[stepRunId]?.evidenceJson ?? '[{"kind":"system_log","reference":""}]',
        ...patch,
      },
    }));
  }

  async function submitDecision(item: ReconciliationItem) {
    const draft = drafts[item.step_run_id];
    if (!draft) {
      setError("Complete the decision details before submitting.");
      return;
    }
    setError("");
    setDecisionMessage(current => ({ ...current, [item.step_run_id]: "" }));
    let evidence: unknown;
    try {
      evidence = JSON.parse(draft.evidenceJson);
    } catch {
      setDecisionMessage(current => ({ ...current, [item.step_run_id]: "Evidence must be valid JSON: an array of { kind, reference, optional sha256 } objects." }));
      return;
    }
    if (!Array.isArray(evidence) || evidence.length < 1 || evidence.length > 20) {
      setDecisionMessage(current => ({ ...current, [item.step_run_id]: "Provide between 1 and 20 evidence references." }));
      return;
    }
    if (draft.reason.trim().length < 3 || draft.reason.trim().length > 1000) {
      setDecisionMessage(current => ({ ...current, [item.step_run_id]: "Enter a reason between 3 and 1000 characters." }));
      return;
    }
    const confirmed = window.confirm(
      "Record this supervisor reconciliation decision permanently? The workflow will remain cancelled and this action cannot be edited or deleted."
    );
    if (!confirmed) return;

    setSubmittingStep(item.step_run_id);
    try {
      const { data, error: sessionError } = await getSupabaseBrowserClient().auth.getSession();
      const token = data.session?.access_token;
      if (sessionError || !token) throw new Error("Your employee session has expired. Sign in again.");
      const response = await fetch("/api/employee/workflows/reconciliation/decision", {
        method: "POST",
        headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
        body: JSON.stringify({
          step_run_id: item.step_run_id,
          outcome: draft.outcome,
          reason: draft.reason.trim(),
          evidence_references: evidence,
        }),
        cache: "no-store",
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error ?? "Decision could not be recorded.");
      setDecisionMessage(current => ({
        ...current,
        [item.step_run_id]: "Decision " + result.decision_id + " recorded. The workflow remains cancelled; no retry or resume was authorized.",
      }));
      setDrafts(current => {
        const next = { ...current };
        delete next[item.step_run_id];
        return next;
      });
      await refresh();
    } catch (cause) {
      setDecisionMessage(current => ({
        ...current,
        [item.step_run_id]: cause instanceof Error ? cause.message : "Decision submission failed.",
      }));
    } finally {
      setSubmittingStep(null);
    }
  }

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
              <summary style={{ cursor: "pointer", fontWeight: 700 }}>
                Supervisor decision history ({item.decision_history?.length ?? 0})
              </summary>
              {(item.decision_history ?? []).map(decision => (
                <div key={decision.id} style={{ background: "#f7f8fa", padding: 12, borderRadius: 8, marginTop: 8 }}>
                  <b>{decision.outcome.replaceAll("_", " ")}</b>
                  <div style={{ color: "#667085", fontSize: 12, marginTop: 4 }}>
                    Decision #{decision.id} · {decision.decided_at} · Reviewer {decision.decided_by_user_id}
                  </div>
                  <p style={{ whiteSpace: "pre-wrap" }}>{decision.reason}</p>
                  <b style={{ fontSize: 12 }}>Evidence references</b>
                  <pre style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontSize: 11 }}>
                    {JSON.stringify(decision.evidence_references, null, 2)}
                  </pre>
                </div>
              ))}
            </details>
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
            <section style={{ borderTop: "1px solid #e1e7ef", marginTop: 18, paddingTop: 16 }}>
              <h3 style={{ margin: "0 0 8px" }}>Supervisor reconciliation decision</h3>
              <p style={{ color: "#8a4b10", background: "#fff7e8", padding: 12, borderRadius: 8 }}>
                Submitting records an immutable finding. It does not resume the workflow, retry the step, or perform compensation.
              </p>
              <label style={{ display: "block", fontWeight: 700, marginTop: 12 }} htmlFor={"outcome-" + item.step_run_id}>Outcome</label>
              <select id={"outcome-" + item.step_run_id}
                value={drafts[item.step_run_id]?.outcome ?? "confirmed_completed"}
                onChange={event => updateDraft(item.step_run_id, { outcome: event.target.value })}
                style={{ width: "100%", padding: 10, border: "1px solid #cbd5e1", borderRadius: 8, marginTop: 6 }}>
                <option value="confirmed_completed">External action confirmed completed</option>
                <option value="confirmed_not_completed">External action confirmed not completed</option>
                <option value="compensation_verified">Compensation independently verified</option>
                <option value="unresolved_escalated">Unresolved — escalate</option>
              </select>
              <label style={{ display: "block", fontWeight: 700, marginTop: 12 }} htmlFor={"reason-" + item.step_run_id}>Decision reason</label>
              <textarea id={"reason-" + item.step_run_id}
                value={drafts[item.step_run_id]?.reason ?? ""}
                onChange={event => updateDraft(item.step_run_id, { reason: event.target.value })}
                minLength={3} maxLength={1000} required rows={3}
                placeholder="Explain what was verified and the basis for this decision."
                style={{ width: "100%", boxSizing: "border-box", padding: 10, border: "1px solid #cbd5e1", borderRadius: 8, marginTop: 6 }} />
              <label style={{ display: "block", fontWeight: 700, marginTop: 12 }} htmlFor={"evidence-" + item.step_run_id}>Evidence references (JSON)</label>
              <textarea id={"evidence-" + item.step_run_id}
                value={drafts[item.step_run_id]?.evidenceJson ?? '[{"kind":"system_log","reference":""}]'}
                onChange={event => updateDraft(item.step_run_id, { evidenceJson: event.target.value })}
                rows={4} spellCheck={false}
                placeholder={'[{"kind":"system_log","reference":"opaque-record-id","sha256":"optional 64-character digest"}]'}
                style={{ width: "100%", boxSizing: "border-box", padding: 10, border: "1px solid #cbd5e1", borderRadius: 8, marginTop: 6, fontFamily: "monospace", fontSize: 12 }} />
              <small style={{ color: "#667085" }}>Use existing evidence identifiers. This field stores references only; it does not upload files or independently validate external records.</small>
              <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 12 }}>
                <button type="button" disabled={submittingStep === item.step_run_id}
                  onClick={() => void submitDecision(item)}
                  style={{ border: 0, borderRadius: 8, padding: "11px 16px", background: "#173b70", color: "white", fontWeight: 700, opacity: submittingStep === item.step_run_id ? 0.6 : 1 }}>
                  {submittingStep === item.step_run_id ? "Recording…" : "Record permanent decision"}
                </button>
              </div>
              {decisionMessage[item.step_run_id] && <p role="status" style={{ background: "#f7f8fa", borderRadius: 8, padding: 12, overflowWrap: "anywhere" }}>{decisionMessage[item.step_run_id]}</p>}
            </section>
          </article>
        ))}
      </section>
    </main>
  );
}
