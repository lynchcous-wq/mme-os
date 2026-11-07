"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type RefundRequest = {
  id: string;
  order_id: string;
  amount_cents: number;
  currency: string;
  reason_code: string;
  status: string;
  requested_at: string;
  provider_status: string | null;
  failure_code: string | null;
};

export default function EmployeeRefundCenterPage() {
  const [items, setItems] = useState<RefundRequest[]>([]);
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [message, setMessage] = useState("Loading refund queue…");
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    setMessage("Loading refund queue…");
    try {
      const response = await fetch("/api/employee/refunds", { credentials: "same-origin", cache: "no-store" });
      const result = await response.json() as { error?: string; requests?: RefundRequest[] };
      if (!response.ok) throw new Error(result.error || "Refund queue unavailable.");
      setItems(result.requests ?? []);
      setMessage((result.requests ?? []).length ? "" : "There are no refund requests in the queue.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to load refund queue.");
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function decide(item: RefundRequest, approve: boolean) {
    const reason = (reasons[item.id] ?? "").trim();
    if (reason.length < 2) {
      setMessage("Enter a decision reason before approving or rejecting.");
      return;
    }
    setBusy(item.id);
    setMessage("");
    try {
      const response = await fetch("/api/employee/refunds", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refundRequestId: item.id, approve, reason }),
      });
      const result = await response.json() as { error?: string; status?: string };
      if (!response.ok) throw new Error(result.error || "Decision was not accepted.");
      setMessage("Refund request " + result.status + ". Approved requests enter the Stripe dispatch queue.");
      await load();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to submit refund decision.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <main style={{ minHeight: "100vh", background: "#f2f5f7", color: "#172432", padding: "32px 18px" }}>
      <section style={{ maxWidth: 1080, margin: "0 auto" }}>
        <Link href="/employee/sign-in" style={{ color: "#1b7181", textDecoration: "none", fontWeight: 700 }}>← Employee portal</Link>
        <header style={{ margin: "24px 0" }}>
          <p style={{ color: "#647586", letterSpacing: 1.4, fontSize: 12, fontWeight: 700 }}>MME OPERATIONS</p>
          <h1 style={{ fontSize: 34, margin: "6px 0" }}>Refund approval center</h1>
          <p style={{ color: "#5e6e7d", lineHeight: 1.6, maxWidth: 760 }}>Review online-order refund requests. Approval is permission checked, and the employee who requested a refund cannot approve their own request. Approved requests are dispatched through the test-mode Stripe worker.</p>
        </header>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, marginBottom: 16 }}>
          <strong>Recent requests</strong>
          <button onClick={() => void load()} style={{ padding: "9px 14px", borderRadius: 8, border: "1px solid #cbd5dc", background: "#fff", cursor: "pointer" }}>Refresh</button>
        </div>
        {message && <p role="status" aria-live="polite" style={{ padding: 14, background: "#fff", border: "1px solid #dce4e9", borderRadius: 10 }}>{message}</p>}
        <div style={{ display: "grid", gap: 14 }}>
          {items.map(item => (
            <article key={item.id} style={{ background: "#fff", border: "1px solid #dce4e9", borderRadius: 12, padding: 18 }}>
              <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 10 }}>
                <div>
                  <strong>Order {item.order_id.slice(0, 8).toUpperCase()}</strong>
                  <p style={{ margin: "6px 0", color: "#5e6e7d" }}>{item.reason_code} · {new Date(item.requested_at).toLocaleString()}</p>
                </div>
                <div style={{ textAlign: "right" }}>
                  <strong style={{ fontSize: 22 }}>{new Intl.NumberFormat("en-US", { style: "currency", currency: item.currency || "USD" }).format(item.amount_cents / 100)}</strong>
                  <p style={{ margin: "6px 0", color: "#5e6e7d" }}>{item.status}{item.provider_status ? " · " + item.provider_status : ""}</p>
                </div>
              </div>
              {item.status === "requested" ? (
                <div style={{ display: "grid", gap: 10, marginTop: 14 }}>
                  <label style={{ display: "grid", gap: 6, fontSize: 13, fontWeight: 600 }}>
                    Decision reason
                    <input value={reasons[item.id] ?? ""} onChange={event => setReasons(current => ({ ...current, [item.id]: event.target.value }))} maxLength={300} placeholder="Enter a short audit reason" style={{ padding: 11, border: "1px solid #cbd5dc", borderRadius: 8, fontSize: 15 }} />
                  </label>
                  <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
                    <button disabled={busy === item.id} onClick={() => void decide(item, true)} style={{ padding: "10px 16px", border: 0, borderRadius: 8, background: "#173f58", color: "#fff", fontWeight: 700, cursor: "pointer" }}>{busy === item.id ? "Saving…" : "Approve refund"}</button>
                    <button disabled={busy === item.id} onClick={() => void decide(item, false)} style={{ padding: "10px 16px", border: "1px solid #cbd5dc", borderRadius: 8, background: "#fff", color: "#263746", fontWeight: 700, cursor: "pointer" }}>Reject</button>
                  </div>
                </div>
              ) : item.failure_code ? <p style={{ color: "#8a4b22", fontSize: 13 }}>Operational reference: {item.failure_code}</p> : null}
            </article>
          ))}
        </div>
      </section>
    </main>
  );
}
