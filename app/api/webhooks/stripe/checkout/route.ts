import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const headers = { "Cache-Control": "no-store, private" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_BODY_BYTES = 262144;

function verifyStripeSignature(raw: string, signature: string, secret: string): boolean {
  const parts = signature.split(",").map(part => part.trim().split("=", 2));
  const timestamp = parts.find(([key]) => key === "t")?.[1];
  const signatures = parts.filter(([key]) => key === "v1").map(([, value]) => value).filter(Boolean);
  if (!timestamp || !/^\d+$/.test(timestamp) || signatures.length === 0) return false;
  const seconds = Number(timestamp);
  if (!Number.isSafeInteger(seconds) || Math.abs(Date.now() / 1000 - seconds) > 300) return false;
  const expected = createHmac("sha256", secret).update(timestamp + "." + raw).digest();
  return signatures.some(candidate => {
    if (!/^[a-f0-9]{64}$/i.test(candidate)) return false;
    const actual = Buffer.from(candidate, "hex");
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  });
}

export async function POST(request: Request) {
  const secret = process.env.STRIPE_CHECKOUT_WEBHOOK_SECRET;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!secret || !secret.startsWith("whsec_") || !serviceKey) {
    return NextResponse.json({ error: "Checkout webhook intake is not configured." }, { status: 503, headers });
  }

  const raw = await request.text();
  if (Buffer.byteLength(raw, "utf8") === 0 || Buffer.byteLength(raw, "utf8") > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Webhook payload size is invalid." }, { status: 413, headers });
  }
  if (!verifyStripeSignature(raw, request.headers.get("stripe-signature") ?? "", secret)) {
    return NextResponse.json({ error: "Invalid Stripe signature." }, { status: 400, headers });
  }

  let event: any;
  try { event = JSON.parse(raw); }
  catch { return NextResponse.json({ error: "Invalid webhook JSON." }, { status: 400, headers }); }

  if (typeof event.id !== "string" || !event.id.startsWith("evt_") || typeof event.type !== "string") {
    return NextResponse.json({ error: "Stripe event identity is invalid." }, { status: 400, headers });
  }

  const supported = new Set([
    "checkout.session.completed",
    "checkout.session.async_payment_succeeded",
    "checkout.session.async_payment_failed",
    "checkout.session.expired",
  ]);
  if (!supported.has(event.type)) return NextResponse.json({ received: true, ignored: true }, { status: 200, headers });

  const session = event.data?.object;
  const orderId = session?.metadata?.mme_order_id;
  const customerId = session?.metadata?.mme_customer_identity_id;
  if (!session || session.object !== "checkout.session" || session.mode !== "payment" ||
      typeof session.id !== "string" || !session.id.startsWith("cs_") ||
      typeof orderId !== "string" || !UUID.test(orderId) ||
      typeof customerId !== "string" || !UUID.test(customerId)) {
    return NextResponse.json({ error: "Checkout session metadata is incomplete." }, { status: 400, headers });
  }

  const amount = Number.isSafeInteger(session.amount_total) && session.amount_total >= 0 ? session.amount_total : 0;
  const currency = typeof session.currency === "string" ? session.currency.toLowerCase() : "";
  if (currency !== "usd" || event.livemode !== false) {
    return NextResponse.json({ error: "Only verified USD test-mode payments are accepted in this release." }, { status: 400, headers });
  }

  try {
    const { url } = supabaseConfig();
    const digest = createHash("sha256").update(raw).digest("hex");
    let rpcName: string;
    let args: Record<string, unknown>;
    if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
      const paymentIntent = typeof session.payment_intent === "string" ? session.payment_intent : "";
      if (session.status !== "complete" || session.payment_status !== "paid" ||
          session.client_reference_id !== orderId || !paymentIntent.startsWith("pi_") || amount <= 0) {
        return NextResponse.json({ error: "Stripe session is not a completed, paid MME checkout." }, { status: 400, headers });
      }
      rpcName = "mme_confirm_stripe_order_payment";
      args = {
        p_provider_event_id: event.id, p_event_type: event.type, p_payload_sha256: digest,
        p_order_id: orderId, p_customer_identity_id: customerId,
        p_checkout_session_id: session.id, p_payment_intent_id: paymentIntent,
        p_amount_cents: amount, p_currency: currency,
      };
    } else {
      rpcName = "mme_process_order_payment_event";
      args = {
        p_provider_event_id: event.id, p_event_type: event.type,
        p_provider_object_id: session.id, p_order_id: orderId,
        p_amount_received_cents: amount, p_currency: currency, p_payload_sha256: digest,
      };
    }

    const response = await fetch(url + "/rest/v1/rpc/" + rpcName, {
      method: "POST",
      headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json" },
      body: JSON.stringify(args), cache: "no-store",
    });
    if (!response.ok) return NextResponse.json({ error: "Verified Stripe payment could not be reconciled to the MME order." }, { status: 503, headers });
    const result = await response.json().catch(() => null);
    return NextResponse.json({ received: true, result }, { status: 200, headers });
  } catch {
    return NextResponse.json({ error: "Checkout webhook processing failed." }, { status: 503, headers });
  }
}
