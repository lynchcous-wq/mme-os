import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { supabaseConfig } from "@/lib/auth/supabase-session";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;
const headers = { "Cache-Control": "no-store, private" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function verifySignature(raw: Buffer, header: string, secret: string): boolean {
  const parts = header.split(",").map(part => part.trim().split("=", 2));
  const timestamp = parts.find(([key]) => key === "t")?.[1];
  const signatures = parts.filter(([key]) => key === "v1").map(([, value]) => value).filter(Boolean);
  if (!timestamp || !/^\d+$/.test(timestamp) || signatures.length === 0) return false;
  const seconds = Number(timestamp);
  if (!Number.isSafeInteger(seconds) || Math.abs(Date.now() / 1000 - seconds) > 300) return false;
  const expected = createHmac("sha256", secret).update(timestamp + ".").update(raw).digest();
  return signatures.some(value => {
    if (!/^[a-f0-9]{64}$/i.test(value)) return false;
    const actual = Buffer.from(value, "hex");
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  });
}

export async function POST(request: Request) {
  const secret = process.env.STRIPE_ORDER_REFUND_WEBHOOK_SECRET;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!secret?.startsWith("whsec_") || !serviceKey) {
    return NextResponse.json({ error: "Order refund webhook is not configured." }, { status: 503, headers });
  }
  const raw = Buffer.from(await request.arrayBuffer());
  if (raw.length === 0 || raw.length > 262144) return NextResponse.json({ error: "Invalid payload size." }, { status: 413, headers });
  if (!verifySignature(raw, request.headers.get("stripe-signature") ?? "", secret)) {
    return NextResponse.json({ error: "Invalid Stripe signature." }, { status: 400, headers });
  }

  let event: any;
  try { event = JSON.parse(raw.toString("utf8")); } catch {
    return NextResponse.json({ error: "Invalid webhook JSON." }, { status: 400, headers });
  }
  if (typeof event.id !== "string" || !event.id.startsWith("evt_")) return NextResponse.json({ error: "Invalid event identity." }, { status: 400, headers });
  if (!["refund.created", "refund.updated"].includes(event.type)) {
    return NextResponse.json({ received: true, ignored: true }, { status: 200, headers });
  }

  const refund = event.data?.object;
  const orderId = refund?.metadata?.mme_order_id;
  const refundRequestId = refund?.metadata?.mme_refund_request_id;
  const paymentIntent = typeof refund?.payment_intent === "string" ? refund.payment_intent : refund?.payment_intent?.id;
  if (!refund || refund.object !== "refund" || typeof refund.id !== "string" || !refund.id.startsWith("re_") ||
      typeof orderId !== "string" || !UUID.test(orderId) ||
      typeof refundRequestId !== "string" || !UUID.test(refundRequestId) ||
      typeof paymentIntent !== "string" || !paymentIntent.startsWith("pi_") ||
      !Number.isSafeInteger(refund.amount) || refund.amount <= 0 || refund.currency !== "usd" ||
      !["pending", "requires_action", "succeeded", "failed", "canceled"].includes(refund.status) ||
      event.livemode !== false) {
    return NextResponse.json({ error: "Refund event does not match the MME test-mode contract." }, { status: 400, headers });
  }

  try {
    const { url } = supabaseConfig();
    const response = await fetch(url + "/rest/v1/rpc/mme_reconcile_order_stripe_refund", {
      method: "POST",
      headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        p_provider_event_id: event.id, p_event_type: event.type,
        p_payload_sha256: createHash("sha256").update(raw).digest("hex"),
        p_refund_request_id: refundRequestId, p_order_id: orderId,
        p_provider_refund_id: refund.id, p_payment_intent_id: paymentIntent,
        p_amount_cents: refund.amount, p_currency: refund.currency, p_provider_status: refund.status,
      }),
      cache: "no-store",
    });
    if (!response.ok) return NextResponse.json({ error: "Verified order refund could not be reconciled." }, { status: 503, headers });
    return NextResponse.json({ received: true, result: await response.json().catch(() => null) }, { status: 200, headers });
  } catch {
    return NextResponse.json({ error: "Order refund reconciliation is temporarily unavailable." }, { status: 503, headers });
  }
}
