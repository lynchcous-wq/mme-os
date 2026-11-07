import { NextRequest, NextResponse } from "next/server";
import { hasSameOrigin, requireBrowserUser, setSessionCookies, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const headers = { "Cache-Control": "no-store, private" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const safeError = (message: string, status: number) => NextResponse.json({ error: message }, { status, headers });

async function customerIdentity(userId: string, url: string, key: string) {
  const linksResponse = await fetch(url + "/rest/v1/mme_customer_account_links?auth_user_id=eq." + encodeURIComponent(userId) + "&link_status=eq.active&select=person_id&limit=2", {
    headers: { apikey: key, Authorization: "Bearer " + key }, cache: "no-store",
  });
  if (!linksResponse.ok) return { error: "Customer account could not be verified.", status: 503 as const };
  const links = await linksResponse.json() as Array<{ person_id: string }>;
  if (links.length !== 1 || !UUID.test(links[0].person_id)) return { error: "An active MME customer account is required.", status: 403 as const };
  const identityResponse = await fetch(url + "/rest/v1/mme_person_identities?person_id=eq." + encodeURIComponent(links[0].person_id) + "&lifecycle_status=eq.active&select=person_id&limit=1", {
    headers: { apikey: key, Authorization: "Bearer " + key }, cache: "no-store",
  });
  if (!identityResponse.ok) return { error: "Customer identity could not be verified.", status: 503 as const };
  const identities = await identityResponse.json() as Array<{ person_id: string }>;
  if (identities.length !== 1) return { error: "Your MME customer identity is not active.", status: 403 as const };
  return { personId: links[0].person_id };
}

export async function GET(request: NextRequest) {
  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return safeError("Sign in to view your orders and refund requests.", 401);
    const { url } = supabaseConfig();
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!key) return safeError("Customer refund portal is not configured.", 503);
    const identity = await customerIdentity(session.user.id, url, key);
    if ("error" in identity) return safeError(identity.error, identity.status);

    const ordersResponse = await fetch(
      url + "/rest/v1/mme_orders?customer_identity_id=eq." + encodeURIComponent(identity.personId) +
      "&select=id,status,total_cents,currency,created_at,updated_at&order=created_at.desc&limit=100",
      { headers: { apikey: key, Authorization: "Bearer " + key }, cache: "no-store" },
    );
    if (!ordersResponse.ok) return safeError("Your order history is temporarily unavailable.", 503);
    const orders = await ordersResponse.json() as Array<{ id: string; status: string; total_cents: number; currency: string; created_at: string; updated_at: string }>;
    const ids = orders.map(order => order.id).filter(id => UUID.test(id));
    if (ids.length === 0) {
      const response = NextResponse.json({ orders: [], refunds: [] }, { headers });
      if (session.refreshed) setSessionCookies(response, session.refreshed);
      return response;
    }
    const refundsResponse = await fetch(
      url + "/rest/v1/mme_order_refund_requests?order_id=in.(" + ids.join(",") +
      ")&select=id,order_id,amount_cents,currency,reason_code,status,provider_status,failure_code,requested_at,updated_at,completed_at&order=requested_at.desc",
      { headers: { apikey: key, Authorization: "Bearer " + key }, cache: "no-store" },
    );
    if (!refundsResponse.ok) return safeError("Refund status is temporarily unavailable.", 503);
    const refunds = await refundsResponse.json();
    const response = NextResponse.json({ orders, refunds }, { headers });
    if (session.refreshed) setSessionCookies(response, session.refreshed);
    return response;
  } catch {
    return safeError("Customer refund portal is temporarily unavailable.", 503);
  }
}

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return safeError("Request origin could not be verified.", 403);
  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return safeError("Sign in before requesting a refund.", 401);
    const raw = await request.text();
    if (Buffer.byteLength(raw, "utf8") > 4000) return safeError("Refund request is too large.", 413);
    let body: { orderId?: unknown; amountCents?: unknown; reasonCode?: unknown; idempotencyKey?: unknown };
    try { body = JSON.parse(raw); } catch { return safeError("Invalid refund request.", 400); }
    if (typeof body.orderId !== "string" || !UUID.test(body.orderId) ||
        !Number.isSafeInteger(body.amountCents) || (body.amountCents as number) <= 0 ||
        typeof body.reasonCode !== "string" || !/^[a-z0-9_-]{2,80}$/i.test(body.reasonCode) ||
        typeof body.idempotencyKey !== "string" || !/^[A-Za-z0-9._:-]{16,128}$/.test(body.idempotencyKey)) {
      return safeError("Provide a valid order, refund amount, reason, and request key.", 400);
    }
    const { url } = supabaseConfig();
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!key) return safeError("Customer refund portal is not configured.", 503);
    const identity = await customerIdentity(session.user.id, url, key);
    if ("error" in identity) return safeError(identity.error, identity.status);

    const orderResponse = await fetch(
      url + "/rest/v1/mme_orders?id=eq." + encodeURIComponent(body.orderId) +
      "&customer_identity_id=eq." + encodeURIComponent(identity.personId) +
      "&select=id,status,total_cents,currency,stripe_payment_intent_id&limit=1",
      { headers: { apikey: key, Authorization: "Bearer " + key }, cache: "no-store" },
    );
    if (!orderResponse.ok) return safeError("Order could not be verified.", 503);
    const orders = await orderResponse.json() as Array<{ id: string; status: string; total_cents: number; currency: string; stripe_payment_intent_id: string | null }>;
    const order = orders[0];
    if (!order) return safeError("Order was not found in your customer account.", 404);
    if (!["paid", "partially_refunded"].includes(order.status) || !order.stripe_payment_intent_id) {
      return safeError("Only completed Stripe-paid orders can be submitted for refund review.", 409);
    }
    if (order.currency !== "USD" || !Number.isSafeInteger(order.total_cents) || (body.amountCents as number) > order.total_cents) {
      return safeError("Refund amount exceeds the eligible order amount.", 409);
    }

    const idempotencyKey = "cust-" + session.user.id + "-" + body.idempotencyKey;
    const rpc = await fetch(url + "/rest/v1/rpc/mme_request_order_refund", {
      method: "POST",
      headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" },
      body: JSON.stringify({
        p_order_id: order.id,
        p_amount_cents: body.amountCents,
        p_reason_code: body.reasonCode,
        p_requested_by: session.user.id,
        p_idempotency_key: idempotencyKey,
      }),
      cache: "no-store",
    });
    if (!rpc.ok) return safeError("Refund request could not be created. Check the remaining refundable balance or contact MME support.", 409);
    const result = await rpc.json();
    const refundRequestId = typeof result === "string" ? result : Array.isArray(result) ? result[0] : null;
    if (typeof refundRequestId !== "string" || !UUID.test(refundRequestId)) return safeError("Refund service returned an invalid confirmation.", 502);
    const response = NextResponse.json({ refundRequestId, status: "requested" }, { status: 201, headers });
    if (session.refreshed) setSessionCookies(response, session.refreshed);
    return response;
  } catch {
    return safeError("Refund request could not be submitted right now.", 503);
  }
}
