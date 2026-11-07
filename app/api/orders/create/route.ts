import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { hasSameOrigin, requireBrowserUser, setSessionCookies, supabaseConfig } from "@/lib/auth/supabase-session";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const headers = { "Cache-Control": "no-store, private" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type Product = { id: string; catalog_product_id: string; sku: string; title: string; condition_grade: string; unit_price_cents: number; currency: string; active: boolean; serialized: boolean };
type Location = { id: string; display_name: string; active: boolean; address_line1: string | null; address_line2: string | null; city: string | null; region: string | null; postal_code: string | null; country_code: string | null };
type Line = { product_id: string; location_id: string; quantity: number };
function error(message: string, status: number) { return NextResponse.json({ error: message }, { status, headers }); }

async function readRows<T>(url: string, key: string, path: string): Promise<T[] | null> {
  const response = await fetch(url + "/rest/v1/" + path, {
    headers: { apikey: key, Authorization: "Bearer " + key, Accept: "application/json" },
    cache: "no-store",
  });
  if (!response.ok) return null;
  return await response.json() as T[];
}

export async function POST(request: NextRequest) {
  if (!hasSameOrigin(request)) return error("Request origin could not be verified.", 403);
  const idempotencyKey = request.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9._:-]{16,128}$/.test(idempotencyKey)) return error("A valid checkout idempotency key is required.", 400);

  let body: { fulfillment_method?: unknown; location_id?: unknown; items?: unknown; shipping_quote_token?: unknown };
  try {
    const raw = await request.text();
    if (Buffer.byteLength(raw, "utf8") > 16000) return error("Order request is too large.", 413);
    body = JSON.parse(raw);
  } catch { return error("Invalid order request.", 400); }

  const method = body.fulfillment_method;
  if (method !== "pickup" && method !== "shipping") return error("Choose pickup or shipping.", 400);
  if (method === "pickup" && (typeof body.location_id !== "string" || !UUID.test(body.location_id))) return error("Choose an eligible MME store for pickup.", 400);
  if (method === "shipping" && (typeof body.shipping_quote_token !== "string" || body.shipping_quote_token.length > 12000)) return error("A current verified shipping quote is required.", 400);
  if (!Array.isArray(body.items) || body.items.length < 1 || body.items.length > 50) return error("Your cart must contain 1 to 50 items.", 400);

  const items = body.items as Line[];
  const seen = new Set<string>();
  for (const item of items) {
    if (!item || typeof item.product_id !== "string" || !UUID.test(item.product_id) ||
        !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 20 ||
        (method === "pickup" && item.location_id !== body.location_id)) return error("Cart contains an invalid product, store, or quantity.", 400);
    if (seen.has(item.product_id)) return error("Combine duplicate product lines before checkout.", 400);
    seen.add(item.product_id);
  }

  try {
    const session = await requireBrowserUser(request);
    if (!session.user) return error("Sign in before placing an order.", 401);
    const { url } = supabaseConfig();
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!serviceKey) return error("Order service is not configured.", 503);

    const links = await readRows<{ person_id: string }>(url, serviceKey,
      "mme_customer_account_links?auth_user_id=eq." + encodeURIComponent(session.user.id) + "&link_status=eq.active&select=person_id&limit=2");
    if (!links || links.length !== 1 || !UUID.test(links[0].person_id)) return error("An active MME customer account is required.", 403);
    const identities = await readRows<{ person_id: string }>(url, serviceKey,
      "mme_person_identities?person_id=eq." + encodeURIComponent(links[0].person_id) + "&lifecycle_status=eq.active&select=person_id&limit=1");
    if (!identities || identities.length !== 1) return error("Your MME customer identity is not active.", 403);
    const customerId = identities[0].person_id;

    let fulfillmentSnapshot: Record<string, unknown>;
    let fulfillmentCents = 0;
    let destination: Record<string, unknown>;
    let inventoryLocationId: string;
    if (method === "pickup") {
      const locations = await readRows<Location>(url, serviceKey,
        "mme_store_locations?id=eq." + encodeURIComponent(body.location_id as string) + "&active=eq.true&select=id,display_name,active,address_line1,address_line2,city,region,postal_code,country_code&limit=1");
      const location = locations?.[0];
      if (!location || !location.address_line1 || !location.city || !location.region || !location.postal_code || location.country_code !== "US") return error("Pickup location needs a complete tax address.", 409);
      inventoryLocationId = location.id;
      destination = { line1: location.address_line1, line2: location.address_line2, city: location.city, region: location.region, postal_code: location.postal_code, country: location.country_code };
      fulfillmentSnapshot = { method: "pickup", location_id: location.id, location_name: location.display_name, destination };
    } else {
      const signingSecret = process.env.MME_SHIPPING_QUOTE_SIGNING_SECRET;
      if (!signingSecret || signingSecret.length < 32) return error("Shipping quote verification is not configured.", 503);
      const tokenParts = (body.shipping_quote_token as string).split(".");
      if (tokenParts.length !== 2 || !tokenParts[0] || !tokenParts[1]) return error("Invalid shipping quote.", 400);
      const expected = createHmac("sha256", signingSecret).update(tokenParts[0]).digest();
      const actual = Buffer.from(tokenParts[1], "base64url");
      if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) return error("Shipping quote signature is invalid.", 400);
      let claims: any;
      try { claims = JSON.parse(Buffer.from(tokenParts[0], "base64url").toString("utf8")); } catch { return error("Shipping quote is invalid.", 400); }
      const fingerprint = createHash("sha256").update(JSON.stringify(
        items.map(item => ({ product_id: item.product_id, quantity: item.quantity })).sort((a, b) => a.product_id.localeCompare(b.product_id))
      )).digest("hex");
      if (claims.customer_id !== customerId || claims.currency !== "USD" || !Number.isSafeInteger(claims.amount_cents) ||
          claims.amount_cents < 0 || !Number.isFinite(claims.expires_at) || claims.expires_at <= Date.now() ||
          claims.cart_fingerprint !== fingerprint || typeof claims.quote_id !== "string" ||
          typeof claims.rate_id !== "string" || typeof claims.validation_id !== "string" ||
          !claims.normalized_address || claims.normalized_address.country !== "US") {
        return error("Shipping quote expired or does not match this customer and cart.", 409);
      }
      inventoryLocationId = process.env.MME_SHIPPING_INVENTORY_LOCATION_ID ?? "";
      if (!UUID.test(inventoryLocationId)) return error("Shipping inventory location is not configured.", 503);
      fulfillmentCents = claims.amount_cents;
      destination = claims.normalized_address;
      fulfillmentSnapshot = {
        method: "shipping", destination, carrier_quote_id: claims.quote_id,
        carrier_rate_id: claims.rate_id, address_validation_id: claims.validation_id,
        quote_expires_at: new Date(claims.expires_at).toISOString(),
      };
    }

    const productIds = items.map(item => item.product_id);
    const products = await readRows<Product>(url, serviceKey,
      "mme_products?id=in.(" + productIds.join(",") + ")&active=eq.true&select=id,catalog_product_id,sku,title,condition_grade,unit_price_cents,currency,active,serialized");
    if (!products || products.length !== items.length) return error("One or more products are no longer available.", 409);
    const catalogIds = products.map(product => product.catalog_product_id).filter(Boolean);
    const catalog = await readRows<{ id: string }>(url, serviceKey,
      "products?id=in.(" + catalogIds.join(",") + ")&catalog_status=eq.published&select=id");
    if (!catalog || catalog.length !== products.length) return error("One or more products are no longer published.", 409);
    const byId = new Map(products.map(product => [product.id, product]));
    const orderLines = items.map(item => {
      const product = byId.get(item.product_id);
      if (!product || product.serialized || product.currency !== "USD" || !Number.isSafeInteger(product.unit_price_cents) || product.unit_price_cents < 0) throw new Error("Unsupported product in cart.");
      return { product_id: item.product_id, location_id: inventoryLocationId, quantity: item.quantity, unit_price_cents: product.unit_price_cents, title: product.title };
    });
    const subtotal = orderLines.reduce((sum, line) => sum + line.unit_price_cents * line.quantity, 0);
    if (!Number.isSafeInteger(subtotal) || subtotal < 1 || subtotal + fulfillmentCents > 9000000000000000) return error("Order total is outside supported limits.", 409);

    const taxUrl = process.env.MME_TAX_CALCULATOR_URL;
    const taxSecret = process.env.MME_TAX_CALCULATOR_SECRET;
    if (!taxUrl || !taxSecret) return error("Tax calculation is not configured. Checkout is safely paused.", 503);
    let taxResponse: Response;
    try {
      taxResponse = await fetch(taxUrl, {
        method: "POST", headers: { Authorization: "Bearer " + taxSecret, "Content-Type": "application/json" },
        body: JSON.stringify({
          currency: "USD", fulfillment_method: method, shipping_amount_cents: fulfillmentCents,
          line_items: orderLines.map(line => ({ reference: line.product_id, quantity: line.quantity, unit_amount: line.unit_price_cents })),
          destination,
        }), cache: "no-store",
      });
    } catch { return error("Tax service is unavailable. No order or inventory reservation was created.", 503); }
    if (!taxResponse.ok) return error("Tax could not be calculated. No order or inventory reservation was created.", 503);
    const tax = await taxResponse.json().catch(() => null) as { tax_cents?: unknown } | null;
    if (!tax || !Number.isSafeInteger(tax.tax_cents) || (tax.tax_cents as number) < 0 || (tax.tax_cents as number) > 9000000000000000) return error("Tax service returned an invalid amount.", 502);

    fulfillmentSnapshot = { ...fulfillmentSnapshot, tax_provider: new URL(taxUrl).host, tax_cents: tax.tax_cents, currency: "USD" };
    const rpc = await fetch(url + "/rest/v1/rpc/mme_create_order_and_reserve", {
      method: "POST",
      headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify({
        p_idempotency_key: idempotencyKey, p_customer_identity_id: customerId,
        p_fulfillment_method: method, p_fulfillment_snapshot: fulfillmentSnapshot,
        p_tax_cents: tax.tax_cents, p_fulfillment_cents: fulfillmentCents, p_discount_cents: 0,
        p_items: orderLines.map(({ product_id, location_id, quantity }) => ({ product_id, location_id, quantity })),
        p_expires_at: new Date(Date.now() + 20 * 60 * 1000).toISOString(),
      }), cache: "no-store",
    });
    if (!rpc.ok) return error("Inventory could not be reserved or order could not be created. Refresh your cart and try again.", 409);
    const result = await rpc.json();
    const orderId = Array.isArray(result) ? result[0] : result;
    const validOrderId = typeof orderId === "string" ? orderId : orderId?.mme_create_order_and_reserve;
    if (typeof validOrderId !== "string" || !UUID.test(validOrderId)) return error("Order creation returned an invalid result.", 502);

    const response = NextResponse.json({
      order_id: validOrderId, subtotal_cents: subtotal, tax_cents: tax.tax_cents,
      fulfillment_cents: fulfillmentCents, total_cents: subtotal + (tax.tax_cents as number) + fulfillmentCents,
      currency: "USD", fulfillment_method: method,
    }, { status: 201, headers });
    if (session.refreshed) setSessionCookies(response, session.refreshed);
    return response;
  } catch {
    return error("Order creation is temporarily unavailable.", 503);
  }
}
