"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type Order = { id: string; status: string; total_cents: number; currency: string; created_at: string; updated_at: string };
type Refund = { id: string; order_id: string; amount_cents: number; currency: string; reason_code: string; status: string; provider_status: string | null; failure_code: string | null; requested_at: string; updated_at: string; completed_at: string | null };

const money = (cents: number, currency = "USD") => new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);

export default function CustomerRefundPortalPage() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [refunds, setRefunds] = useState<Refund[]>([]);
  const [selected, setSelected] = useState("");
  const [amount, setAmount] = useState("");
  const [reason, setReason] = useState("item_issue");
  const [message, setMessage] = useState("Loading your orders…");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const response = await fetch("/api/account/refunds", { credentials: "same-origin", cache: "no-store" });
      const result = await response.json() as { error?: string; orders?: Order[]; refunds?: Refund[] };
      if (!response.ok) throw new Error(result.error || "Unable to load account details.");
      setOrders(result.orders ?? []);
      setRefunds(result.refunds ?? []);
      setMessage("");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to load your refund portal.");
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const eligible = orders.filter(order => ["paid", "partially_refunded"].includes(order.status));
  const selectedOrder = eligible.find(order => order.id === selected);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedOrder || !amount || !Number.isFinite(Number(amount)) || Number(amount) <= 0) {
      setMessage("Choose an eligible order and enter a valid refund amount.");
      return;
    }
    const cents = Math.round(Number(amount) * 100);
    if (!Number.isSafeInteger(cents) || cents < 1 || cents > selectedOrder.total_cents) {
      setMessage("Enter an amount within the order total.");
      return;
    }
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch("/api/account/refunds", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          orderId: selectedOrder.id,
          amountCents: cents,
          reasonCode: reason,
          idempotencyKey: crypto.randomUUID(),
        }),
      });
      const result = await response.json() as { error?: string; status?: string };
      if (!response.ok) throw new Error(result.error || "Refund request was not accepted.");
      setMessage("Your refund request was submitted for MME review. It is not yet approved or refunded.");
      setAmount("");
      await load();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to submit your refund request.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main style={{ minHeight: "100vh", background: "#f3f6f8", color: "#172432", padding: "30px 18px" }}>
      <section style={{ maxWidth: 1000, margin: "0 auto" }}>
        <Link href="/account" style={{ color: "#1b7181", textDecoration: "none", fontWeight: 700 }}>← Customer account</Link>
        <header style={{ margin: "24px 0" }}>
          <p style={{ color: "#647586", fontSize: 12, fontWeight: 700, letterSpacing: 1.4 }}>MUCH MORE ELECTRONICS</p>
          <h1 style={{ fontSize: 34, margin: "6px 0" }}>Orders & refunds</h1>
          <p style={{ color: "#5e6e7d", lineHeight: 1.6, maxWidth: 760 }}>View your MME order history, submit a refund request for an eligible paid order, and follow its review and Stripe processing status. Submitting a request does not guarantee approval.</p>
        </header>

        {message && <p role="status" aria-live="polite" style={{ padding: 14, background: "#fff", border: "1px solid #dce4e9", borderRadius: 10 }}>{message}</p>}

        <section style={{ background: "#fff", border: "1px solid #dce4e9", borderRadius: 12, padding: 20, margin: "18px 0" }}>
          <h2 style={{ fontSize: 21, marginTop: 0 }}>Request a refund</h2>
          <form onSubmit={submit} style={{ display: "grid", gap: 13 }}>
            <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Eligible order
              <select value={selected} onChange={event => setSelected(event.target.value)} required style={{ padding: 12, border: "1px solid #cbd5dc", borderRadius: 8, fontSize: 15 }}>
                <option value="">Choose an order</option>
                {eligible.map(order => <option key={order.id} value={order.id}>{order.id.slice(0, 8).toUpperCase()} · {money(order.total_cents, order.currency)} · {order.status}</option>)}
              </select>
            </label>
            <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Requested amount (USD)
              <input type="number" min="0.01" step="0.01" max={selectedOrder ? (selectedOrder.total_cents / 100).toFixed(2) : undefined} value={amount} onChange={event => setAmount(event.target.value)} required placeholder="0.00" style={{ padding: 12, border: "1px solid #cbd5dc", borderRadius: 8, fontSize: 15 }} />
            </label>
            <label style={{ display: "grid", gap: 6, fontWeight: 600, fontSize: 13 }}>Reason
              <select value={reason} onChange={event => setReason(event.target.value)} style={{ padding: 12, border: "1px solid #cbd5dc", borderRadius: 8, fontSize: 15 }}>
                <option value="item_issue">Item issue</option>
                <option value="wrong_item">Wrong item received</option>
                <option value="not_received">Order not received</option>
                <option value="duplicate_charge">Duplicate charge</option>
                <option value="other">Other</option>
              </select>
            </label>
            <button type="submit" disabled={busy || !selectedOrder} style={{ justifySelf: "start", padding: "12px 18px", border: 0, borderRadius: 8, background: "#173f58", color: "#fff", fontWeight: 700, cursor: busy ? "wait" : "pointer" }}>{busy ? "Submitting…" : "Submit refund request"}</button>
          </form>
        </section>

        <section style={{ marginTop: 24 }}>
          <h2 style={{ fontSize: 22 }}>Refund status</h2>
          {refunds.length === 0 ? <p style={{ color: "#607180" }}>No refund requests have been submitted for your orders.</p> : <div style={{ display: "grid", gap: 12 }}>
            {refunds.map(refund => (
              <article key={refund.id} style={{ background: "#fff", border: "1px solid #dce4e9", borderRadius: 12, padding: 18 }}>
                <div style={{ display: "flex", justifyContent: "space-between", gap: 10, flexWrap: "wrap" }}>
                  <div><strong>Order {refund.order_id.slice(0, 8).toUpperCase()}</strong><p style={{ color: "#607180", margin: "5px 0" }}>{refund.reason_code.replaceAll("_", " ")} · Requested {new Date(refund.requested_at).toLocaleDateString()}</p></div>
                  <div style={{ textAlign: "right" }}><strong style={{ fontSize: 21 }}>{money(refund.amount_cents, refund.currency)}</strong><p style={{ color: "#607180", margin: "5px 0" }}>{refund.status.replaceAll("_", " ")}{refund.provider_status ? " · Stripe: " + refund.provider_status : ""}</p></div>
                </div>
                {refund.status === "requested" && <p style={{ color: "#607180", fontSize: 13 }}>Awaiting MME review. No refund has been issued yet.</p>}
                {refund.status === "approved" || refund.status === "processing" || refund.status === "pending_provider" ? <p style={{ color: "#607180", fontSize: 13 }}>Approved or sent for provider processing. Final status will update after Stripe confirms the outcome.</p> : null}
                {refund.status === "succeeded" && <p style={{ color: "#1b7152", fontSize: 13 }}>Stripe confirmed this refund{refund.completed_at ? " on " + new Date(refund.completed_at).toLocaleDateString() : ""}.</p>}
                {["rejected", "failed", "manual_review"].includes(refund.status) && <p style={{ color: "#8a4b22", fontSize: 13 }}>This request requires further attention. Contact MME support with the order reference above.</p>}
              </article>
            ))}
          </div>}
        </section>

        <section style={{ marginTop: 28 }}>
          <h2 style={{ fontSize: 22 }}>Order history</h2>
          <div style={{ display: "grid", gap: 10 }}>
            {orders.map(order => <article key={order.id} style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 10, background: "#fff", border: "1px solid #dce4e9", borderRadius: 10, padding: 14 }}>
              <div><strong>Order {order.id.slice(0, 8).toUpperCase()}</strong><p style={{ color: "#607180", margin: "5px 0" }}>{new Date(order.created_at).toLocaleDateString()} · {order.status.replaceAll("_", " ")}</p></div>
              <strong>{money(order.total_cents, order.currency)}</strong>
            </article>)}
            {orders.length === 0 && <p style={{ color: "#607180" }}>No orders are linked to this customer account yet.</p>}
          </div>
        </section>
      </section>
    </main>
  );
}
