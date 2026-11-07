import { NextRequest, NextResponse } from "next/server";
import { hasSameOrigin, requireBrowserUser, setSessionCookies, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const headers = { "Cache-Control": "no-store, private" };

type Order = {
  id: string;
  customer_identity_id: string;
  status: string;
  total_cents: number;
  currency: string;
  fulfillment_method: string;
};

function jsonError(message: string, status: number) {
  return NextResponse.json({ error: message }, { status, headers });
}

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return jsonError("Request origin could not be verified.", 403);

  const stripeKey = process.env.STRIPE_SECRET_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!stripeKey || !stripeKey.startsWith("sk_test_") || !serviceKey) return jsonError("Test-mode Stripe Checkout is not configured.", 503);

  let body: { order_id?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonError("Invalid checkout request.", 400);
  }
  if (typeof body.order_id !== "string" || !UUID.test(body.order_id)) {
    return jsonError("A valid order is required.", 400);
  }

  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return jsonError("Sign in before checkout.", 401);

    const { url } = supabaseConfig();
    const restHeaders = { apikey: serviceKey, Authorization: "Bearer " + serviceKey };
    const linksResponse = await fetch(
      `${url}/rest/v1/mme_customer_account_links?auth_user_id=eq.${encodeURIComponent(session.user.id)}&link_status=eq.active&select=person_id&limit=2`,
      { headers: restHeaders, cache: "no-store" },
    );
    if (!linksResponse.ok) return jsonError("Customer account could not be verified.", 503);
    const links = await linksResponse.json() as Array<{ person_id: string }>;
    if (links.length !== 1 || !UUID.test(links[0].person_id)) {
      return jsonError("Your login is not linked to one active MME customer account.", 403);
    }

    const identityResponse = await fetch(
      `${url}/rest/v1/mme_person_identities?person_id=eq.${encodeURIComponent(links[0].person_id)}&lifecycle_status=eq.active&select=person_id&limit=1`,
      { headers: restHeaders, cache: "no-store" },
    );
    if (!identityResponse.ok) return jsonError("Customer identity could not be verified.", 503);
    const identities = await identityResponse.json() as Array<{ person_id: string }>;
    if (identities.length !== 1) return jsonError("Your MME customer identity is not active.", 403);

    const orderResponse = await fetch(
      `${url}/rest/v1/mme_orders?id=eq.${encodeURIComponent(body.order_id)}&customer_identity_id=eq.${encodeURIComponent(links[0].person_id)}&select=id,customer_identity_id,status,total_cents,currency,fulfillment_method&limit=1`,
      { headers: restHeaders, cache: "no-store" },
    );
    if (!orderResponse.ok) return jsonError("Order could not be verified.", 503);
    const orders = await orderResponse.json() as Order[];
    const order = orders[0];
    if (!order) return jsonError("Order was not found for this customer.", 404);
    if (order.status !== "pending_payment") return jsonError("This order is not awaiting payment.", 409);
    if (order.currency !== "USD" || !Number.isSafeInteger(order.total_cents) || order.total_cents <= 0) {
      return jsonError("Order total is not eligible for online checkout.", 409);
    }

    const reservationResponse = await fetch(
      `${url}/rest/v1/mme_inventory_reservations?order_id=eq.${encodeURIComponent(order.id)}&status=eq.active&expires_at=gt.${encodeURIComponent(new Date().toISOString())}&select=id&limit=1`,
      { headers: restHeaders, cache: "no-store" },
    );
    if (!reservationResponse.ok) return jsonError("Inventory reservation could not be verified.", 503);
    const reservations = await reservationResponse.json() as Array<{ id: string }>;
    if (reservations.length !== 1) return jsonError("Inventory reservation is missing or expired. Revalidate your cart.", 409);

    const origin = request.nextUrl.origin;
    const form = new URLSearchParams();
    form.set("mode", "payment");
    form.set("success_url", `${origin}/account/orders?checkout=success&session_id={CHECKOUT_SESSION_ID}`);
    form.set("cancel_url", `${origin}/cart?checkout=cancelled`);
    form.set("client_reference_id", order.id);
    form.set("expires_at", String(Math.floor(Date.now() / 1000) + 20 * 60));
    form.set("line_items[0][price_data][currency]", "usd");
    form.set("line_items[0][price_data][unit_amount]", String(order.total_cents));
    form.set("line_items[0][price_data][product_data][name]", "Much More Electronics order " + order.id.slice(0, 8));
    form.set("line_items[0][quantity]", "1");
    form.set("metadata[mme_order_id]", order.id);
    form.set("metadata[mme_customer_identity_id]", links[0].person_id);
    form.set("payment_intent_data[metadata][mme_order_id]", order.id);
    form.set("payment_intent_data[metadata][mme_customer_identity_id]", links[0].person_id);

    const stripeResponse = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + stripeKey,
        "Content-Type": "application/x-www-form-urlencoded",
        "Idempotency-Key": "mme-checkout-order-" + order.id,
      },
      body: form.toString(),
      cache: "no-store",
    });
    const stripeBody = await stripeResponse.json().catch(() => ({})) as { id?: unknown; url?: unknown };
    if (!stripeResponse.ok || typeof stripeBody.id !== "string" || typeof stripeBody.url !== "string") {
      return jsonError("Secure checkout could not be started. Your order and inventory reservation remain unchanged.", 502);
    }

    const response = NextResponse.json({ checkoutUrl: stripeBody.url, sessionId: stripeBody.id }, { headers });
    if (session.refreshed) setSessionCookies(response, session.refreshed);
    return response;
  } catch {
    return jsonError("Checkout is temporarily unavailable.", 503);
  }
}
