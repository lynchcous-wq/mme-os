import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const headers = { "Cache-Control": "no-store, private" };
const MAX_BODY_BYTES = 1024 * 1024;

function verifyStripeSignature(raw: string, signature: string, secret: string) {
  const parts = signature.split(",").map((part) => part.split("=", 2));
  const timestamp = parts.find(([key]) => key === "t")?.[1];
  const signatures = parts.filter(([key]) => key === "v1").map(([, value]) => value).filter(Boolean);
  if (!timestamp || !/^\d+$/.test(timestamp) || signatures.length === 0) return false;
  if (Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp)) > 300) return false;
  const expected = createHmac("sha256", secret).update(timestamp + "." + raw).digest();
  return signatures.some((candidate) => {
    try {
      const actual = Buffer.from(candidate, "hex");
      return actual.length === expected.length && timingSafeEqual(actual, expected);
    } catch {
      return false;
    }
  });
}

type StripeSession = {
  id?: unknown;
  mode?: unknown;
  payment_status?: unknown;
  amount_total?: unknown;
  currency?: unknown;
  metadata?: Record<string, unknown>;
};

export async function POST(request: Request) {
  const secret = process.env.STRIPE_CHECKOUT_WEBHOOK_SECRET;
  const baseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!secret || !baseUrl || !serviceKey) {
    return NextResponse.json({ error: "Checkout webhook intake is not configured." }, { status: 503, headers });
  }

  const raw = await request.text();
  if (Buffer.byteLength(raw, "utf8") > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Webhook payload too large." }, { status: 413, headers });
  }
  if (!verifyStripeSignature(raw, request.headers.get("stripe-signature") ?? "", secret)) {
    return NextResponse.json({ error: "Invalid webhook signature." }, { status: 400, headers });
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "Invalid webhook JSON." }, { status: 400, headers });
  }

  const eventId = typeof event.id === "string" ? event.id : "";
  const eventType = typeof event.type === "string" ? event.type : "";
  const data = event.data && typeof event.data === "object" ? event.data as Record<string, unknown> : null;
  const session = data?.object && typeof data.object === "object" ? data.object as StripeSession : null;
  if (!eventId || !session || typeof session.id !== "string" || session.mode !== "payment") {
    return NextResponse.json({ received: true, ignored: "not_a_checkout_payment_session" }, { status: 200, headers });
  }

  const supported = new Set([
    "checkout.session.completed",
    "checkout.session.async_payment_succeeded",
    "checkout.session.async_payment_failed",
    "checkout.session.expired",
  ]);
  if (!supported.has(eventType)) {
    return NextResponse.json({ received: true, ignored: "unsupported_event_type" }, { status: 200, headers });
  }

  const orderId = typeof session.metadata?.mme_order_id === "string" ? session.metadata.mme_order_id : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(orderId)) {
    return NextResponse.json({ received: true, ignored: "missing_order_metadata" }, { status: 200, headers });
  }

  // A Checkout Session can complete before an asynchronous payment settles.
  // Never mark the order paid from "completed" unless Stripe says payment_status=paid.
  if (eventType === "checkout.session.completed" && session.payment_status !== "paid") {
    return NextResponse.json({ received: true, awaiting_async_payment: true }, { status: 200, headers });
  }

  const amount = typeof session.amount_total === "number" && Number.isSafeInteger(session.amount_total)
    ? session.amount_total : 0;
  const currency = typeof session.currency === "string" ? session.currency.toLowerCase() : "usd";
  if (currency !== "usd") {
    return NextResponse.json({ error: "Unsupported checkout currency." }, { status: 400, headers });
  }

  try {
    const payloadHash = createHash("sha256").update(raw).digest("hex");
    const response = await fetch(baseUrl.replace(/\/$/, "") + "/rest/v1/rpc/mme_process_order_payment_event", {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: "Bearer " + serviceKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_provider_event_id: eventId,
        p_event_type: eventType,
        p_provider_object_id: session.id,
        p_order_id: orderId,
        p_amount_received_cents: amount,
        p_currency: currency,
        p_payload_sha256: payloadHash,
      }),
      cache: "no-store",
    });
    if (!response.ok) {
      return NextResponse.json({ error: "Verified checkout event could not be processed." }, { status: 503, headers });
    }
    const outcome = await response.json();
    return NextResponse.json({ received: true, outcome }, { status: 200, headers });
  } catch {
    return NextResponse.json({ error: "Checkout webhook processing failed." }, { status: 503, headers });
  }
}
