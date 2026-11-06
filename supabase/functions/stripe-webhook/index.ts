import Stripe from "npm:stripe@17.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import { readBoundedBody, sha256Hex, verifyStripeWebhook } from "../_shared/stripe-webhook-security.ts";

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
  if (!signature || signature.length > 4096) return json({ error: "missing_or_invalid_signature_header" }, 400);

  // Bound webhook input before buffering it, then verify the exact raw bytes.
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > 1_048_576) {
    return json({ error: "webhook_payload_too_large" }, 413);
  }
  let rawBody: string | null;
  try {
    rawBody = await readBoundedBody(request, 1_048_576);
  } catch {
    return json({ error: "webhook_payload_invalid_encoding" }, 400);
  }
  if (rawBody === null) return json({ error: "webhook_payload_too_large_or_empty" }, 413);
  let event: Stripe.Event;
  try {
    event = await verifyStripeWebhook(rawBody, signature, webhookSecret, stripeSecret);
  } catch {
    return json({ error: "invalid_webhook_signature" }, 400);
  }

  if (event.livemode !== (expectedLiveMode === "true")) {
    return json({ error: "stripe_mode_mismatch" }, 400);
  }
  if (expectedAccountId && event.account !== expectedAccountId) {
    return json({ error: "stripe_account_mismatch" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const payloadHash = await sha256Hex(rawBody);

  // Refund events are accepted only when the refund ID and original PaymentIntent
  // match a server-created binding to an approved MME return case.
  if (["refund.created", "refund.updated", "refund.failed"].includes(event.type)) {
    const refund = event.data.object as Stripe.Refund;
    const paymentIntentId = typeof refund.payment_intent === "string"
      ? refund.payment_intent
      : refund.payment_intent?.id;
    const systemActorId = Deno.env.get("MME_STRIPE_SYSTEM_ACTOR_ID");

    if (!refund.id || !paymentIntentId || refund.currency !== "usd" ||
        !Number.isSafeInteger(refund.amount) || refund.amount <= 0) {
      return json({ error: "unsupported_refund_payload" }, 400);
    }
    if (!systemActorId) return json({ error: "refund_adapter_actor_not_configured" }, 503);

    const { data: refundBinding, error: refundBindingError } = await supabase
      .from("mme_return_refund_provider_bindings")
      .select("approval_id, provider_payment_intent_id, provider_refund_id, amount_cents, currency")
      .eq("provider", "stripe")
      .eq("provider_refund_id", refund.id)
      .maybeSingle();

    if (refundBindingError) return json({ error: "refund_binding_lookup_failed" }, 500);
    if (!refundBinding) return json({ error: "unbound_stripe_refund" }, 409);
    if (refundBinding.provider_payment_intent_id !== paymentIntentId ||
        refundBinding.provider_refund_id !== refund.id ||
        refundBinding.amount_cents !== refund.amount ||
        refundBinding.currency !== "USD") {
      return json({ error: "stripe_refund_binding_mismatch" }, 409);
    }

    // Stripe may deliver refund.created after the refund has already succeeded.
    // Prefer the provider object's verified state over the event name.
    const refundEventType = event.type === "refund.failed" ||
        refund.status === "failed" || refund.status === "canceled"
      ? "refund_failed"
      : refund.status === "succeeded"
      ? "refund_succeeded"
      : "refund_submitted";

    const { data: refundOutcome, error: refundProcessingError } = await supabase.rpc(
      "mme_record_return_refund_event",
      {
        p_approval_id: refundBinding.approval_id,
        p_provider: "stripe",
        p_provider_event_id: event.id,
        p_provider_refund_id: refund.id,
        p_event_type: refundEventType,
        p_amount_cents: refund.amount,
        p_currency: refund.currency,
        p_payload_sha256: payloadHash,
        p_actor_identity_id: systemActorId,
      },
    );

    if (refundProcessingError) {
      return json({ error: "refund_event_processing_failed" }, 500);
    }
    return json({ received: true, refund_outcome: refundOutcome, refund_status: refund.status });
  }

  if (["charge.dispute.created", "charge.dispute.updated", "charge.dispute.closed"].includes(event.type)) {
    const dispute = event.data.object as Stripe.Dispute;
    const paymentIntentId = typeof dispute.payment_intent === "string"
      ? dispute.payment_intent
      : dispute.payment_intent?.id;
    const systemActorId = Deno.env.get("MME_STRIPE_SYSTEM_ACTOR_ID");
    const allowedStatuses = ["warning_needs_response", "needs_response", "under_review", "won", "lost"];
    const disputeStatus = allowedStatuses.includes(dispute.status)
      ? dispute.status
      : dispute.status === "warning_under_review"
      ? "under_review"
      : "unknown";

    if (!dispute.id || !paymentIntentId || dispute.currency !== "usd" ||
        !Number.isSafeInteger(dispute.amount) || dispute.amount <= 0) {
      return json({ error: "unsupported_dispute_payload" }, 400);
    }
    if (!systemActorId) return json({ error: "dispute_adapter_actor_not_configured" }, 503);

    const { data: disputeOutcome, error: disputeProcessingError } = await supabase.rpc(
      "mme_record_stripe_dispute_event",
      {
        p_event_id: event.id,
        p_dispute_id: dispute.id,
        p_payment_intent_id: paymentIntentId,
        p_status: disputeStatus,
        p_reason: dispute.reason ?? null,
        p_amount_cents: dispute.amount,
        p_currency: dispute.currency,
        p_payload_sha256: payloadHash,
        p_actor_identity_id: systemActorId,
      },
    );
    if (disputeProcessingError) {
      return json({ error: "dispute_event_processing_failed" }, 500);
    }
    return json({ received: true, dispute_outcome: disputeOutcome, dispute_status: disputeStatus });
  }

  if (![ "payment_intent.succeeded", "payment_intent.payment_failed" ].includes(event.type)) {
    return json({ received: true, ignored: true });
  }

  const intent = event.data.object as Stripe.PaymentIntent;
  if (!intent.id || intent.currency !== "usd") {
    return json({ error: "unsupported_payment_intent" }, 400);
  }

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
      p_payload_sha256: payloadHash,
    },
  );

  if (processingError) {
    return json({ error: "payment_event_processing_failed" }, 500);
  }

  const refundReview = typeof outcome === "string" &&
    (outcome.includes("refund_review") || outcome.includes("mismatch"));
  if (refundReview) {
    return json({ received: true, outcome, requires_review: true });
  }

  // Finalize fulfillment after the signed Stripe event has committed the paid
  // order state. This runs for duplicate webhook deliveries too, so a transient
  // finalization failure is safely retried without consuming stock twice.
  if (event.type === "payment_intent.succeeded") {
    const systemActorId = Deno.env.get("MME_STRIPE_SYSTEM_ACTOR_ID");
    if (!systemActorId) return json({ error: "order_confirmation_actor_not_configured" }, 503);
    const { data: currentOrder, error: orderReadError } = await supabase
      .from("mme_orders").select("status").eq("id", binding.order_id).maybeSingle();
    if (orderReadError) return json({ error: "order_confirmation_status_lookup_failed" }, 500);
    if (currentOrder?.status === "paid" || currentOrder?.status === "partially_refunded") {
      const { data: fulfillmentId, error: finalizeError } = await supabase.rpc(
        "mme_finalize_paid_order_fulfillment",
        { p_order_id: binding.order_id, p_system_actor_identity_id: systemActorId },
      );
      if (finalizeError || !fulfillmentId) {
        return json({ error: "paid_order_fulfillment_finalization_failed" }, 500);
      }
      return json({ received: true, outcome, fulfillment_id: fulfillmentId });
    }
  }
  return json({ received: true, outcome });
});
