import { createHmac, timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { hasSameOrigin, requireBrowserUser, setSessionCookies, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const headers = { "Cache-Control": "no-store, private" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ZIP = /^\d{5}(?:-\d{4})?$/;
const MAX_LINES = 30;
type Address = { line1: string; line2?: string; city: string; region: string; postal_code: string; country: "US" };
type Product = { id: string; title: string; sku: string; active: boolean; serialized: boolean; shipping_weight_oz: number | null; shipping_length_in: number | null; shipping_width_in: number | null; shipping_height_in: number | null; shipping_hazmat: boolean };
type Rate = { rate_id: string; service_name: string; amount_cents: number; currency: string; estimated_days: number | null };
function fail(message: string, status: number) { return NextResponse.json({ error: message }, { status, headers }); }
async function rows<T>(url: string, key: string, path: string): Promise<T[] | null> {
  const response = await fetch(url + "/rest/v1/" + path, { headers: { apikey: key, Authorization: "Bearer " + key, Accept: "application/json" }, cache: "no-store" });
  if (!response.ok) return null;
  return await response.json() as T[];
}
function secureServiceUrl(value: string | undefined) {
  if (!value) return null;
  try { const url = new URL(value); return url.protocol === "https:" ? url.toString().replace(/\/$/, "") : null; }
  catch { return null; }
}
function signQuote(payload: string, secret: string) {
  return createHmac("sha256", secret).update(payload).digest("base64url");
}
function safeEqual(a: string, b: string) {
  const aa = Buffer.from(a); const bb = Buffer.from(b);
  return aa.length === bb.length && timingSafeEqual(aa, bb);
}

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return fail("Request origin could not be verified.", 403);
  let body: { address?: unknown; items?: unknown };
  try {
    const raw = await request.text();
    if (Buffer.byteLength(raw, "utf8") > 12000) return fail("Shipping quote request is too large.", 413);
    body = JSON.parse(raw);
  } catch { return fail("Invalid shipping quote request.", 400); }

  const address = body.address as Partial<Address> | undefined;
  if (!address || typeof address.line1 !== "string" || address.line1.trim().length < 3 || address.line1.length > 120 ||
      (address.line2 !== undefined && (typeof address.line2 !== "string" || address.line2.length > 120)) ||
      typeof address.city !== "string" || address.city.trim().length < 2 || address.city.length > 80 ||
      typeof address.region !== "string" || !/^[A-Za-z]{2}$/.test(address.region) ||
      typeof address.postal_code !== "string" || !ZIP.test(address.postal_code) || address.country !== "US") {
    return fail("Enter a valid US shipping address.", 400);
  }
  if (!Array.isArray(body.items) || body.items.length < 1 || body.items.length > MAX_LINES) return fail("Shipping cart must contain 1 to 30 products.", 400);
  const items = body.items as Array<{ product_id?: unknown; quantity?: unknown }>;
  const ids = new Set<string>();
  for (const item of items) {
    if (!item || typeof item.product_id !== "string" || !UUID.test(item.product_id) ||
        !Number.isInteger(item.quantity) || (item.quantity as number) < 1 || (item.quantity as number) > 10 ||
        ids.has(item.product_id)) return fail("Shipping cart contains an invalid or duplicate item.", 400);
    ids.add(item.product_id);
  }

  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return fail("Sign in before requesting shipping rates.", 401);
    const { url } = supabaseConfig();
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!key) return fail("Shipping service is not configured.", 503);
    const links = await rows<{ person_id: string }>(url, key,
      "mme_customer_account_links?auth_user_id=eq." + encodeURIComponent(session.user.id) + "&link_status=eq.active&select=person_id&limit=2");
    if (!links || links.length !== 1) return fail("An active MME customer account is required.", 403);
    const identities = await rows<{ person_id: string }>(url, key,
      "mme_person_identities?person_id=eq." + encodeURIComponent(links[0].person_id) + "&lifecycle_status=eq.active&select=person_id&limit=1");
    if (!identities || identities.length !== 1) return fail("Your MME customer identity is not active.", 403);

    const productIds = [...ids];
    const products = await rows<Product>(url, key,
      "mme_products?id=in.(" + productIds.join(",") + ")&active=eq.true&select=id,title,sku,active,serialized,shipping_weight_oz,shipping_length_in,shipping_width_in,shipping_height_in,shipping_hazmat");
    if (!products || products.length !== items.length) return fail("One or more products are no longer available.", 409);
    const byId = new Map(products.map(product => [product.id, product]));
    const packages = items.map(item => {
      const product = byId.get(item.product_id as string);
      if (!product || product.serialized || product.shipping_hazmat ||
          !Number.isInteger(product.shipping_weight_oz) || !product.shipping_weight_oz ||
          !product.shipping_length_in || !product.shipping_width_in || !product.shipping_height_in) {
        throw new Error("A product is not configured for shipping.");
      }
      return {
        product_id: product.id, sku: product.sku, description: product.title,
        quantity: item.quantity,
        weight_oz: product.shipping_weight_oz,
        dimensions_in: { length: product.shipping_length_in, width: product.shipping_width_in, height: product.shipping_height_in },
      };
    });

    const addressUrl = secureServiceUrl(process.env.MME_ADDRESS_VALIDATOR_URL);
    const addressSecret = process.env.MME_ADDRESS_VALIDATOR_SECRET;
    const carrierUrl = secureServiceUrl(process.env.MME_CARRIER_RATE_URL);
    const carrierSecret = process.env.MME_CARRIER_RATE_SECRET;
    const signingSecret = process.env.MME_SHIPPING_QUOTE_SIGNING_SECRET;
    if (!addressUrl || !addressSecret || !carrierUrl || !carrierSecret || !signingSecret || signingSecret.length < 32) {
      return fail("Address validation and carrier-rate services are not configured. Pickup remains available.", 503);
    }

    const validationResponse = await fetch(addressUrl, {
      method: "POST", headers: { Authorization: "Bearer " + addressSecret, "Content-Type": "application/json" },
      body: JSON.stringify({ address }), cache: "no-store",
    });
    if (!validationResponse.ok) return fail("Shipping address could not be validated.", 422);
    const validation = await validationResponse.json().catch(() => null) as { deliverable?: unknown; verified?: unknown; normalized_address?: Address; validation_id?: string } | null;
    if (!validation || validation.deliverable !== true || validation.verified !== true || !validation.normalized_address || typeof validation.validation_id !== "string") {
      return fail("This address could not be verified as deliverable. Please correct it or choose store pickup.", 422);
    }
    const normalized = validation.normalized_address;
    if (normalized.country !== "US" || !ZIP.test(normalized.postal_code ?? "") || !normalized.line1 || !normalized.city || !normalized.region) {
      return fail("Address validator returned an incomplete destination.", 502);
    }

    const rateResponse = await fetch(carrierUrl, {
      method: "POST", headers: { Authorization: "Bearer " + carrierSecret, "Content-Type": "application/json" },
      body: JSON.stringify({ ship_to: normalized, packages, currency: "USD" }), cache: "no-store",
    });
    if (!rateResponse.ok) return fail("Carrier rates are temporarily unavailable.", 503);
    const rateBody = await rateResponse.json().catch(() => null) as { rates?: Rate[]; quote_id?: string } | null;
    if (!rateBody || typeof rateBody.quote_id !== "string" || !Array.isArray(rateBody.rates) || rateBody.rates.length < 1 || rateBody.rates.length > 20) {
      return fail("Carrier service returned no usable shipping options.", 502);
    }

    const expiresAt = Date.now() + 10 * 60 * 1000;
    const rates = rateBody.rates.map(rate => {
      if (!rate || typeof rate.rate_id !== "string" || rate.rate_id.length > 160 ||
          typeof rate.service_name !== "string" || rate.service_name.length > 100 ||
          !Number.isSafeInteger(rate.amount_cents) || rate.amount_cents < 0 || rate.currency !== "USD" ||
          (rate.estimated_days !== null && (!Number.isInteger(rate.estimated_days) || rate.estimated_days < 1 || rate.estimated_days > 60))) {
        throw new Error("Carrier returned an invalid rate.");
      }
      const payload = Buffer.from(JSON.stringify({
        customer_id: identities[0].person_id, quote_id: rateBody.quote_id, rate_id: rate.rate_id,
        amount_cents: rate.amount_cents, currency: "USD", validation_id: validation.validation_id,
        expires_at: expiresAt,
      })).toString("base64url");
      return { service_name: rate.service_name, amount_cents: rate.amount_cents, currency: "USD", estimated_days: rate.estimated_days, quote_token: payload + "." + signQuote(payload, signingSecret) };
    });
    const response = NextResponse.json({ fulfillment_method: "shipping", verified_address: normalized, rates, expires_at: new Date(expiresAt).toISOString() }, { headers });
    if (session.refreshed) setSessionCookies(response, session.refreshed);
    return response;
  } catch (cause) {
    if (cause instanceof Error && cause.message === "A product is not configured for shipping.") return fail("At least one item is pickup-only or missing a verified shipping package profile.", 409);
    return fail("Shipping quote could not be completed. Store pickup remains available.", 503);
  }
}
