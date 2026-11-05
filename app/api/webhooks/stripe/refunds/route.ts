import { createHmac, timingSafeEqual, createHash } from "node:crypto";
import { NextResponse } from "next/server";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  const base = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!secret || !base || !key) return NextResponse.json({ error: "Not configured" }, { status: 503 });
  const raw = Buffer.from(await request.arrayBuffer());
  if (raw.length > 262144) return NextResponse.json({ error: "Too large" }, { status: 413 });
  const header = request.headers.get("stripe-signature") ?? "";
  const fields = header.split(",").map(x => x.split("=", 2));
  const ts = fields.find(x => x[0] === "t")?.[1] ?? "";
  const signatures = fields.filter(x => x[0] === "v1").map(x => x[1]);
  if (!/^\d+$/.test(ts) || Math.abs(Date.now()/1000 - Number(ts)) > 300) return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  const expected = createHmac("sha256", secret).update(ts + ".").update(raw).digest();
  const valid = signatures.some(s => { try { const got = Buffer.from(s, "hex"); return got.length === expected.length && timingSafeEqual(got, expected); } catch { return false; } });
  if (!valid) return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  let event: any;
  try { event = JSON.parse(raw.toString("utf8")); } catch { return NextResponse.json({ error: "Invalid JSON" }, { status: 400 }); }
  const refund = event?.data?.object ?? {};
  const metadata = refund.metadata ?? {};
  const requestId = metadata.mme_refund_request_id;
  const payment = typeof refund.payment_intent === "string" ? refund.payment_intent : refund.payment_intent?.id;
  const account = event.account;
  const amount = refund.amount;
  const currency = String(refund.currency ?? "").toUpperCase();
  const status = refund.status === "succeeded" ? "succeeded" : refund.status === "failed" || refund.status === "canceled" ? "failed" : "pending";
  if (!event.id || !["refund.created", "refund.updated"].includes(event.type) || !account || !requestId || !refund.id || !payment || !Number.isSafeInteger(amount) || amount <= 0 || !/^[A-Z]{3}$/.test(currency)) return NextResponse.json({ error: "Unsupported event" }, { status: 400 });
  const response = await fetch(base + "/rest/v1/rpc/mme_pos_reconcile_stripe_refund_webhook", {
    method: "POST", headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify({ p_provider_event_id: event.id, p_event_type: event.type, p_payload_sha256: createHash("sha256").update(raw).digest("hex"), p_refund_request_id: requestId, p_provider_account_reference: account, p_provider_refund_reference: refund.id, p_provider_payment_reference: payment, p_amount_minor: amount, p_currency: currency, p_provider_status: status }),
    cache: "no-store"
  });
  if (!response.ok) return NextResponse.json({ error: "Reconciliation unavailable" }, { status: 503 });
  return NextResponse.json({ received: true, result: await response.json() }, { status: 202, headers: { "Cache-Control": "no-store" } });
}