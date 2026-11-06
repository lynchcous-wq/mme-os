import Stripe from "npm:stripe@17.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.49.1";

type Json = Record<string, unknown>;
const response = (body: Json, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const safeEqual = (a: string, b: string) => {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
};

Deno.serve(async (request) => {
  if (request.method !== "POST") return response({ error: "method_not_allowed" }, 405);
  const expectedSecret = Deno.env.get("MME_CHECKOUT_RECOVERY_SECRET") ?? "";
  const suppliedSecret = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (expectedSecret.length < 32 || !safeEqual(suppliedSecret, expectedSecret)) {
    return response({ error: "unauthorized" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL"), serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY"), liveMode = Deno.env.get("STRIPE_LIVEMODE");
  if (!url || !serviceKey || !stripeKey || !["true", "false"].includes(liveMode ?? "")) {
    return response({ error: "recovery_worker_not_configured" }, 503);
  }
  const keyMatchesMode = liveMode === "true"
    ? stripeKey.startsWith("sk_live_") || stripeKey.startsWith("rk_live_")
    : stripeKey.startsWith("sk_test_") || stripeKey.startsWith("rk_test_");
  if (!keyMatchesMode) return response({ error: "stripe_mode_configuration_mismatch" }, 503);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const stripe = new Stripe(stripeKey, { apiVersion: "2025-02-24.acacia" });
  const { data: reservations, error } = await admin.from("mme_inventory_reservations")
    .select("order_id,expires_at,status")
    .eq("status", "active").lte("expires_at", new Date().toISOString())
    .order("expires_at", { ascending: true }).limit(100);
  if (error) return response({ error: "expired_reservations_lookup_failed" }, 500);

  const result = { scanned: reservations?.length ?? 0, expired: 0, quarantined: 0, skipped: 0 };
  for (const reservation of reservations ?? []) {
    const orderId = reservation.order_id as string;
    const { data: order, error: orderError } = await admin.from("mme_orders")
      .select("id,status,total_cents,currency,customer_identity_id").eq("id", orderId).maybeSingle();
    if (orderError || !order || order.status !== "pending_payment") { result.skipped++; continue; }

    const { data: binding, error: bindingError } = await admin.from("mme_order_payment_intents")
      .select("provider_object_id,expected_amount_cents,currency")
      .eq("order_id", orderId).maybeSingle();
    if (bindingError) { result.skipped++; continue; }

    const recordCase = async (caseType: string, providerId: string | null, providerStatus: string | null, details: Json) => {
      const { error: caseError } = await admin.from("mme_checkout_recovery_cases").upsert({
        order_id: orderId, provider: "stripe", provider_object_id: providerId,
        case_type: caseType, provider_status: providerStatus, details,
        status: "open", last_error: typeof details.error === "string" ? details.error.slice(0, 500) : null,
        updated_at: new Date().toISOString(),
      }, { onConflict: "order_id,case_type" });
      return !caseError;
    };

    if (bindingError) { result.skipped++; continue; }
    let resolvedBinding = binding;
    if (!resolvedBinding) {
      // Stripe search is a recovery path for a PaymentIntent created successfully
      // when the subsequent database binding RPC timed out or failed.
      try {
        const found = await stripe.paymentIntents.search({
          query: "metadata['mme_order_id']:'" + orderId + "'",
          limit: 10,
        });
        const matching = found.data.filter((candidate) =>
          candidate.metadata.mme_order_id === orderId &&
          candidate.amount === order.total_cents && candidate.currency === "usd" &&
          candidate.livemode === (liveMode === "true")
        );
        if (matching.length === 1 && order.customer_identity_id) {
          const { error: bindError } = await admin.rpc("mme_bind_order_payment_intent", {
            p_order_id: orderId,
            p_provider_object_id: matching[0].id,
            p_expected_amount_cents: order.total_cents,
            p_currency: "USD",
            p_customer_identity_id: order.customer_identity_id,
          });
          if (!bindError) {
            resolvedBinding = {
              provider_object_id: matching[0].id,
              expected_amount_cents: order.total_cents,
              currency: "USD",
            };
          }
        } else if (matching.length > 1) {
          await recordCase("payment_intent_status_unresolved", null, null, {
            message: "Multiple Stripe PaymentIntents match this order; automatic selection is unsafe.",
            matching_intent_ids: matching.map((candidate) => candidate.id),
          });
          result.quarantined++;
          continue;
        }
      } catch {
        // Search is eventually consistent and may be unavailable. Keep stock reserved.
      }
    }
    if (!resolvedBinding) {
      await recordCase("payment_intent_binding_missing", null, null, {
        message: "No bound PaymentIntent was found in the database or Stripe search. Inventory remains reserved pending reconciliation.",
      });
      result.quarantined++;
      continue;
    }
    if (resolvedBinding.currency !== "USD" || resolvedBinding.expected_amount_cents !== order.total_cents) {
      await recordCase("payment_intent_status_unresolved", resolvedBinding.provider_object_id, null, {
        message: "PaymentIntent binding does not match the order total/currency.",
      });
      result.quarantined++;
      continue;
    }

    let intent: Stripe.PaymentIntent;
    try {
      intent = await stripe.paymentIntents.retrieve(resolvedBinding.provider_object_id);
    } catch (e) {
      await recordCase("payment_intent_status_unresolved", resolvedBinding.provider_object_id, null, {
        error: e instanceof Error ? e.message : "Provider lookup failed",
      });
      result.quarantined++;
      continue;
    }

    if (intent.amount !== order.total_cents || intent.currency !== "usd" ||
        intent.metadata.mme_order_id !== orderId || intent.livemode !== (liveMode === "true")) {
      await recordCase("payment_intent_status_unresolved", intent.id, intent.status, {
        message: "Provider intent amount, currency, order metadata, or mode does not match the order.",
      });
      result.quarantined++;
      continue;
    }

    if (intent.status === "succeeded") {
      await recordCase("payment_succeeded_after_reservation_expiry", intent.id, intent.status, {
        amount_received: intent.amount_received,
        message: "Payment succeeded after reservation expiry. Keep inventory quarantined; manual refund/recovery decision required.",
      });
      result.quarantined++;
      continue;
    }

    if (intent.status !== "canceled") {
      try {
        intent = await stripe.paymentIntents.cancel(intent.id, {}, {
          idempotencyKey: "mme-expire-cancel-" + orderId,
        });
      } catch (e) {
        await recordCase("payment_intent_cancel_failed", intent.id, intent.status, {
          error: e instanceof Error ? e.message : "PaymentIntent cancellation failed",
          message: "Reservation retained until provider payment state is safely resolved.",
        });
        result.quarantined++;
        continue;
      }
    }

    if (intent.status !== "canceled") {
      await recordCase("payment_intent_cancel_failed", intent.id, intent.status, {
        message: "Provider did not confirm PaymentIntent cancellation; reservation retained.",
      });
      result.quarantined++;
      continue;
    }

    const { data: expired, error: expireError } = await admin.rpc(
      "mme_expire_single_inventory_reservation", { p_order_id: orderId },
    );
    if (expireError || expired !== true) {
      await recordCase("payment_intent_status_unresolved", intent.id, intent.status, {
        error: expireError?.message ?? "Reservation was not expired by the database",
      });
      result.quarantined++;
      continue;
    }
    await admin.from("mme_checkout_recovery_cases").update({
      status: "resolved", resolved_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    }).eq("order_id", orderId).eq("status", "open");
    result.expired++;
  }
  return response({ success: true, ...result });
});
