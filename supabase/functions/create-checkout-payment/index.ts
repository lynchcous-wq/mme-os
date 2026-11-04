import Stripe from "npm:stripe@17.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.49.1";

const baseHeaders = { "Content-Type": "application/json", "Vary": "Origin" };
const reply = (body: unknown, status = 200, origin?: string) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...baseHeaders, ...(origin ? { "Access-Control-Allow-Origin": origin } : {}) },
  });

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") ?? undefined;
  const allowedOrigins = (Deno.env.get("MME_CHECKOUT_ALLOWED_ORIGINS") ?? "")
    .split(",").map((value) => value.trim()).filter(Boolean);
  if (origin && !allowedOrigins.includes(origin)) return reply({ error: "origin_not_allowed" }, 403);
  const corsHeaders = {
    ...baseHeaders,
    ...(origin ? { "Access-Control-Allow-Origin": origin } : {}),
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-idempotency-key",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405, origin);

  const auth = req.headers.get("authorization");
  const idempotencyKey = req.headers.get("x-idempotency-key") ?? "";
  if (!auth?.startsWith("Bearer ") || idempotencyKey.trim().length < 8 ||
      idempotencyKey.length > 128 || idempotencyKey !== idempotencyKey.trim()) {
    return reply({ error: "authentication_and_idempotency_required" }, 401, origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const pricingUrl = Deno.env.get("MME_CHECKOUT_PRICING_URL");
  const pricingSecret = Deno.env.get("MME_CHECKOUT_PRICING_SECRET");
  const expectedLiveMode = Deno.env.get("STRIPE_LIVEMODE");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !stripeKey || !pricingUrl || !pricingSecret ||
      !["true", "false"].includes(expectedLiveMode ?? "")) {
    return reply({ error: "checkout_not_configured" }, 503, origin);
  }
  const keyMatchesMode = expectedLiveMode === "true"
    ? stripeKey.startsWith("sk_live_") || stripeKey.startsWith("rk_live_")
    : stripeKey.startsWith("sk_test_") || stripeKey.startsWith("rk_test_");
  if (!keyMatchesMode) return reply({ error: "stripe_mode_configuration_mismatch" }, 503, origin);

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > 64_000) {
    return reply({ error: "request_too_large" }, 413, origin);
  }
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return reply({ error: "invalid_json" }, 400, origin);
  }
  if (!body || typeof body !== "object" || Array.isArray(body) ||
      !Array.isArray((body as any).items) ||
      (body as any).items.length < 1 || (body as any).items.length > 50 ||
      !["pickup", "shipping"].includes((body as any).fulfillment_method) ||
      !(body as any).fulfillment_details || typeof (body as any).fulfillment_details !== "object" ||
      Array.isArray((body as any).fulfillment_details)) {
    return reply({ error: "invalid_checkout_request" }, 400, origin);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return reply({ error: "unauthorized" }, 401, origin);

  let priced: any;
  try {
    const response = await fetch(pricingUrl, {
      method: "POST",
      headers: { Authorization: "Bearer " + pricingSecret, "Content-Type": "application/json" },
      body: JSON.stringify({
        auth_user_id: userData.user.id,
        items: (body as any).items,
        fulfillment_method: (body as any).fulfillment_method,
        fulfillment_details: (body as any).fulfillment_details,
      }),
    });
    if (!response.ok) return reply({ error: "trusted_pricing_unavailable" }, 503, origin);
    priced = await response.json();
  } catch {
    return reply({ error: "trusted_pricing_unavailable" }, 503, origin);
  }

  if (!priced || typeof priced.customer_identity_id !== "string" ||
      !Array.isArray(priced.items) || priced.items.length < 1 || priced.items.length > 50 ||
      !Number.isSafeInteger(priced.tax_cents) || priced.tax_cents < 0 ||
      !Number.isSafeInteger(priced.fulfillment_cents) || priced.fulfillment_cents < 0 ||
      !Number.isSafeInteger(priced.discount_cents) || priced.discount_cents < 0 ||
      !priced.fulfillment_snapshot || typeof priced.fulfillment_snapshot !== "object" ||
      Array.isArray(priced.fulfillment_snapshot)) {
    return reply({ error: "trusted_pricing_response_invalid" }, 502, origin);
  }

  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (priced.items.some((item: any) =>
    !item || !uuidPattern.test(item.product_id ?? "") ||
    !uuidPattern.test(item.location_id ?? "") ||
    !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 20 ||
    (item.serialized_unit_id !== undefined &&
      (!uuidPattern.test(item.serialized_unit_id) || item.quantity !== 1))
  )) {
    return reply({ error: "invalid_priced_items" }, 502, origin);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const reservationExpiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
  const { data: orderId, error: orderError } = await admin.rpc(
    "mme_create_mixed_order_and_reserve",
    {
      p_idempotency_key: idempotencyKey,
      p_customer_identity_id: priced.customer_identity_id,
      p_fulfillment_method: (body as any).fulfillment_method,
      p_fulfillment_snapshot: priced.fulfillment_snapshot,
      p_tax_cents: priced.tax_cents,
      p_fulfillment_cents: priced.fulfillment_cents,
      p_discount_cents: priced.discount_cents,
      p_items: priced.items,
      p_expires_at: reservationExpiresAt,
    },
  );
  if (orderError || !orderId) return reply({ error: "order_creation_or_reservation_failed" }, 409, origin);

  const { data: order, error: readError } = await admin
    .from("mme_orders")
    .select("id,total_cents,currency,status,customer_identity_id")
    .eq("id", orderId)
    .single();
  if (readError || !order || order.status !== "pending_payment" ||
      order.customer_identity_id !== priced.customer_identity_id) {
    return reply({ error: "order_not_payable" }, 409, origin);
  }

  const stripe = new Stripe(stripeKey, { apiVersion: "2025-02-24.acacia" });
  let intent: Stripe.PaymentIntent;
  try {
    intent = await stripe.paymentIntents.create(
      {
        amount: order.total_cents,
        currency: "usd",
        automatic_payment_methods: { enabled: true },
        metadata: { mme_order_id: order.id },
      },
      { idempotencyKey: "mme-order-" + order.id },
    );
  } catch {
    return reply({ error: "payment_intent_creation_failed", order_id: order.id }, 502, origin);
  }
  if (intent.livemode !== (expectedLiveMode === "true") ||
      intent.amount !== order.total_cents || intent.currency !== "usd" || !intent.client_secret) {
    return reply({ error: "payment_intent_validation_failed", order_id: order.id }, 502, origin);
  }

  const { error: bindError } = await admin.rpc("mme_bind_order_payment_intent", {
    p_order_id: order.id,
    p_provider_object_id: intent.id,
    p_expected_amount_cents: order.total_cents,
    p_currency: order.currency,
    p_customer_identity_id: order.customer_identity_id,
  });
  if (bindError) {
    return reply({ error: "payment_binding_failed_reconciliation_required", order_id: order.id }, 503, origin);
  }

  return reply({
    order_id: order.id,
    payment_intent_id: intent.id,
    client_secret: intent.client_secret,
    amount_cents: order.total_cents,
    currency: order.currency,
    reservation_expires_at: reservationExpiresAt,
  }, 200, origin);
});
