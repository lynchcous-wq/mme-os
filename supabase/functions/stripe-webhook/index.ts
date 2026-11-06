import Stripe from "npm:stripe@17.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "null",
  "Access-Control-Allow-Headers": "stripe-signature, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY");
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const expectedLiveMode = Deno.env.get("STRIPE_LIVEMODE");
  const expectedAccountId = Deno.env.get("STRIPE_EXPECTED_ACCOUNT_ID");

  if (!stripeSecret || !webhookSecret || !supabaseUrl || !serviceRoleKey ||
      !["true", "false"].includes(expectedLiveMode ?? "")) {
    return json({ error: "payment_service_not_configured" }, 503);
  }

  const signature = request.headers.get("stripe-signature");
  if (!signature) return json({ error: "missing_signature" }, 400);

  // Verify the exact raw request bytes before parsing or trusting event fields.
  const rawBody = await request.text();
  const stripe = new Stripe(stripeSecret, { apiVersion: "2025-02-24.acacia" });
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      rawBody,
      signature,
      webhookSecret,
      undefined,
      Stripe.createSubtleCryptoProvider(),
    );
  } catch {
    return json({ error: "invalid_webhook_signature" }, 400);
  }

  if (event.livemode !== (expectedLiveMode === "true")) {
    return json({ error: "stripe_mode_mismatch" }, 400);
  }
  if (expectedAccountId && event.account !== expectedAccountId) {
    return json({ error: "stripe_account_mismatch" }, 400);
  }

  if (!["payment_intent.succeeded", "payment_intent.payment_failed"].includes(event.type)) {
    return json({ received: true, ignored: true });
  }

  const intent = event.data.object as Stripe.PaymentIntent;
  if (!intent.id || intent.currency !== "usd") {
    return json({ error: "unsupported_payment_intent" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: binding, error: bindingError } = await supabase
    .from("mme_order_payment_intents")
    .select("order_id, expected_amount_cents, currency")
    .eq("provider", "stripe")
    .eq("provider_object_id", intent.id)
    .maybeSingle();

  if (bindingError) return json({ error: "payment_binding_lookup_failed" }, 500);
  if (!binding) return json({ error: "unbound_payment_intent" }, 409);
  if (binding.currency !== "USD" || binding.expected_amount_cents !== intent.amount) {
    return json({ error: "payment_intent_binding_mismatch" }, 409);
  }

  const amountForProcessor = event.type === "payment_intent.succeeded"
    ? intent.amount_received
    : 0;

  const { data: outcome, error: processingError } = await supabase.rpc(
    "mme_process_unified_order_payment_event",
    {
      p_provider_event_id: event.id,
      p_event_type: event.type,
      p_payment_intent_id: intent.id,
      p_order_id: binding.order_id,
      p_amount_received_cents: amountForProcessor,
      p_currency: intent.currency,
      p_payload_sha256: await sha256Hex(rawBody),
    },
  );

  if (processingError) {
    // Non-2xx prompts Stripe to retry; database event deduplication protects replays.
    return json({ error: "payment_event_processing_failed" }, 500);
  }

  const refundReview = typeof outcome === "string" &&
    (outcome.includes("refund_review") || outcome.includes("mismatch"));
  if (refundReview) {
    // Acknowledge only after the database has durably recorded the review state.
    return json({ received: true, outcome, requires_review: true });
  }

  return json({ received: true, outcome });
});
