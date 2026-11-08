import { createClient } from "npm:@supabase/supabase-js@2.49.1";

type CartLine = {
  product_id: string;
  location_id: string;
  quantity: number;
  serialized_unit_id?: string;
};
type FulfillmentMethod = "pickup" | "shipping";
type JsonObject = Record<string, unknown>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_BODY = 32_000;
const reply = (body: JsonObject, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

function safeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let diff = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}

function isObject(value: unknown): value is JsonObject {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function cleanText(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const result = value.trim();
  return result.length > 0 && result.length <= max ? result : null;
}

function secureServiceUrl(value: string | undefined): URL | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password) return null;
    return url;
  } catch {
    return null;
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const expectedSecret = Deno.env.get("MME_CHECKOUT_PRICING_SECRET") ?? "";
  const suppliedSecret = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (expectedSecret.length < 32 || !safeEqual(suppliedSecret, expectedSecret)) {
    return reply({ error: "unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const quoteUrl = secureServiceUrl(Deno.env.get("MME_CHECKOUT_QUOTE_URL"));
  const quoteSecret = Deno.env.get("MME_CHECKOUT_QUOTE_SECRET") ?? "";
  if (!supabaseUrl || !serviceRoleKey || !quoteUrl || quoteSecret.length < 32) {
    return reply({ error: "trusted_pricing_not_configured" }, 503);
  }

  const contentLength = request.headers.get("content-length");
  if (contentLength && (!/^\d+$/.test(contentLength) || Number(contentLength) > MAX_BODY)) {
    return reply({ error: "request_too_large" }, 413);
  }
  let body: unknown;
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY) return reply({ error: "request_too_large" }, 413);
    body = JSON.parse(raw);
  } catch {
    return reply({ error: "invalid_json" }, 400);
  }

  if (!isObject(body) || !UUID.test(String(body.auth_user_id ?? "")) ||
      !Array.isArray(body.items) || body.items.length < 1 || body.items.length > 50 ||
      !["pickup", "shipping"].includes(String(body.fulfillment_method)) ||
      !isObject(body.fulfillment_details)) {
    return reply({ error: "invalid_pricing_request" }, 400);
  }

  const method = body.fulfillment_method as FulfillmentMethod;
  const details = body.fulfillment_details;
  const lines = body.items as CartLine[];
  const seen = new Set<string>();
  for (const line of lines) {
    if (!isObject(line) || !UUID.test(String(line.product_id ?? "")) ||
        !UUID.test(String(line.location_id ?? "")) ||
        !Number.isInteger(line.quantity) || line.quantity < 1 || line.quantity > 20 ||
        (line.serialized_unit_id !== undefined &&
          (!UUID.test(String(line.serialized_unit_id)) || line.quantity !== 1))) {
      return reply({ error: "invalid_cart_line" }, 400);
    }
    const key = `${line.product_id}:${line.location_id}:${line.serialized_unit_id ?? "aggregate"}`;
    if (seen.has(key)) return reply({ error: "duplicate_cart_line" }, 400);
    seen.add(key);
  }

  const customerName = cleanText(details.customer_name ?? (isObject(details.shipping_address) ? details.shipping_address.name : null), 180);
  const customerEmail = cleanText(details.customer_email ?? (isObject(details.shipping_address) ? details.shipping_address.email : null), 254);
  const customerPhone = cleanText(details.customer_phone ?? (isObject(details.shipping_address) ? details.shipping_address.phone : null), 40);
  if (!customerName || !customerEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail) || !customerPhone) {
    return reply({ error: "valid_customer_contact_required" }, 400);
  }

  let shippingAddress: JsonObject | null = null;
  if (method === "pickup") {
    if (!UUID.test(String(details.pickup_location_id ?? ""))) return reply({ error: "pickup_location_required" }, 400);
  } else {
    if (!isObject(details.shipping_address)) return reply({ error: "shipping_address_required" }, 400);
    const address = details.shipping_address;
    const line1 = cleanText(address.line1, 180);
    const city = cleanText(address.city, 100);
    const region = cleanText(address.state, 80);
    const postal = cleanText(address.postal_code, 24);
    const country = cleanText(address.country, 2)?.toUpperCase() ?? null;
    if (!line1 || !city || !region || !postal || !country || !/^[A-Z]{2}$/.test(country)) {
      return reply({ error: "complete_shipping_address_required" }, 400);
    }
    shippingAddress = {
      name: customerName, email: customerEmail, phone: customerPhone,
      line1, line2: cleanText(address.line2, 180), city, state: region,
      postal_code: postal, country,
    };
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    const { data: identity, error: identityError } = await admin
      .from("mme_person_identities")
      .select("id,security_status")
      .eq("auth_user_id", body.auth_user_id)
      .maybeSingle();
    if (identityError || !identity || identity.security_status !== "active") {
      return reply({ error: "customer_identity_unavailable" }, 403);
    }
    const { data: customer, error: customerError } = await admin
      .from("mme_customer_relationships")
      .select("id,status")
      .eq("person_identity_id", identity.id)
      .maybeSingle();
    if (customerError || !customer || customer.status !== "active") {
      return reply({ error: "active_customer_relationship_required" }, 403);
    }

    const productIds = [...new Set(lines.map((line) => line.product_id))];
    const locationIds = [...new Set(lines.map((line) => line.location_id))];
    const unitIds = [...new Set(lines.flatMap((line) => line.serialized_unit_id ? [line.serialized_unit_id] : []))];
    const [productsResult, locationsResult, balancesResult, unitsResult] = await Promise.all([
      admin.from("mme_products")
        .select("id,catalog_product_id,sku,title,unit_price_cents,currency,serialized,active")
        .in("id", productIds).eq("active", true),
      admin.from("mme_store_locations")
        .select("id,display_name,active").in("id", locationIds).eq("active", true),
      admin.from("mme_inventory_balances")
        .select("product_id,location_id,on_hand_quantity,reserved_quantity")
        .in("product_id", productIds).in("location_id", locationIds),
      unitIds.length
        ? admin.from("mme_serialized_units")
            .select("id,product_id,location_id,unit_status")
            .in("id", unitIds).eq("unit_status", "in_stock")
        : Promise.resolve({ data: [], error: null }),
    ]);
    if (productsResult.error || locationsResult.error || balancesResult.error || unitsResult.error) {
      return reply({ error: "inventory_validation_unavailable" }, 503);
    }

    const products = productsResult.data ?? [];
    const locations = locationsResult.data ?? [];
    const balances = balancesResult.data ?? [];
    const units = unitsResult.data ?? [];
    const productById = new Map(products.map((row) => [row.id, row]));
    const locationById = new Map(locations.map((row) => [row.id, row]));
    const balanceByKey = new Map(balances.map((row) => [`${row.product_id}:${row.location_id}`, row]));
    const unitById = new Map(units.map((row) => [row.id, row]));
    const catalogIds = [...new Set(products.flatMap((row) => row.catalog_product_id ? [row.catalog_product_id] : []))];
    if (catalogIds.length !== productIds.length) return reply({ error: "product_not_published_for_sale" }, 409);
    const { data: catalogRows, error: catalogError } = await admin
      .from("products").select("id,catalog_status").in("id", catalogIds).eq("catalog_status", "published");
    if (catalogError || (catalogRows ?? []).length !== catalogIds.length) {
      return reply({ error: "product_not_published_for_sale" }, 409);
    }

    const canonicalItems: Array<{ product_id: string; location_id: string; quantity: number; serialized_unit_id?: string }> = [];
    const quoteLines: Array<JsonObject> = [];
    let subtotalCents = 0;
    for (const line of lines) {
      const product = productById.get(line.product_id);
      const location = locationById.get(line.location_id);
      if (!product || !location || product.currency !== "USD") return reply({ error: "product_or_location_unavailable" }, 409);
      const unitPrice = Number(product.unit_price_cents);
      if (!Number.isSafeInteger(unitPrice) || unitPrice < 0) return reply({ error: "invalid_product_price" }, 503);
      let available = 0;
      if (product.serialized) {
        const unit = line.serialized_unit_id ? unitById.get(line.serialized_unit_id) : null;
        if (!unit || unit.product_id !== line.product_id || unit.location_id !== line.location_id || line.quantity !== 1) {
          return reply({ error: "serialized_unit_unavailable" }, 409);
        }
        available = 1;
      } else {
        if (line.serialized_unit_id) return reply({ error: "serialized_unit_product_mismatch" }, 409);
        const balance = balanceByKey.get(`${line.product_id}:${line.location_id}`);
        available = balance ? Math.max(0, balance.on_hand_quantity - balance.reserved_quantity) : 0;
        if (line.quantity > available) return reply({ error: "insufficient_inventory" }, 409);
      }
      const lineTotal = unitPrice * line.quantity;
      if (!Number.isSafeInteger(lineTotal) || !Number.isSafeInteger(subtotalCents + lineTotal)) {
        return reply({ error: "order_amount_out_of_range" }, 422);
      }
      subtotalCents += lineTotal;
      canonicalItems.push({
        product_id: line.product_id, location_id: line.location_id,
        quantity: line.quantity, ...(line.serialized_unit_id ? { serialized_unit_id: line.serialized_unit_id } : {}),
      });
      quoteLines.push({
        product_id: product.id, sku: product.sku, title: product.title,
        quantity: line.quantity, unit_price_cents: unitPrice, line_total_cents: lineTotal,
        location_id: location.id, location_name: location.display_name,
        serialized_unit_id: line.serialized_unit_id ?? null,
      });
    }

    if (method === "pickup") {
      const pickupId = String(details.pickup_location_id);
      if (!locationById.has(pickupId) || lines.some((line) => line.location_id !== pickupId)) {
        return reply({ error: "pickup_location_inventory_mismatch" }, 409);
      }
    }

    const quoteResponse = await fetch(quoteUrl, {
      method: "POST",
      headers: { Authorization: `Bearer ${quoteSecret}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        customer_identity_id: identity.id,
        customer_relationship_id: customer.id,
        currency: "USD",
        items: quoteLines,
        subtotal_cents: subtotalCents,
        fulfillment_method: method,
        pickup_location_id: method === "pickup" ? details.pickup_location_id : null,
        shipping_address: shippingAddress,
        customer_contact: { name: customerName, email: customerEmail, phone: customerPhone },
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!quoteResponse.ok) return reply({ error: "tax_shipping_discount_quote_unavailable" }, 503);
    const quote = await quoteResponse.json();
    if (!isObject(quote) || !Number.isSafeInteger(quote.tax_cents) || Number(quote.tax_cents) < 0 ||
        !Number.isSafeInteger(quote.fulfillment_cents) || Number(quote.fulfillment_cents) < 0 ||
        !Number.isSafeInteger(quote.discount_cents) || Number(quote.discount_cents) < 0 ||
        (Number(quote.discount_cents) > 0 && !cleanText(quote.discount_reference, 180)) ||
        (quote.discount_snapshot !== undefined && !isObject(quote.discount_snapshot))) {
      return reply({ error: "tax_shipping_discount_quote_invalid" }, 502);
    }
    const totalBeforeDiscount = subtotalCents + Number(quote.tax_cents) + Number(quote.fulfillment_cents);
    if (!Number.isSafeInteger(totalBeforeDiscount) || Number(quote.discount_cents) > totalBeforeDiscount) {
      return reply({ error: "pricing_quote_amount_invalid" }, 502);
    }

    const fulfillmentSnapshot: JsonObject = {
      method,
      customer_name: customerName,
      customer_email: customerEmail,
      customer_phone: customerPhone,
      ...(method === "pickup"
        ? { pickup_location_id: details.pickup_location_id, pickup_location_name: locationById.get(String(details.pickup_location_id))?.display_name }
        : { shipping_address: shippingAddress }),
      quote_reference: cleanText(quote.quote_reference, 180),
      discount_reference: cleanText(quote.discount_reference, 180),
      discount_snapshot: isObject(quote.discount_snapshot) ? quote.discount_snapshot : {},
    };

    return reply({
      customer_identity_id: identity.id,
      items: canonicalItems,
      expected_subtotal_cents: subtotalCents,
      tax_cents: quote.tax_cents,
      fulfillment_cents: quote.fulfillment_cents,
      discount_cents: quote.discount_cents,
      fulfillment_snapshot: fulfillmentSnapshot,
    });
  } catch {
    return reply({ error: "trusted_pricing_internal_error" }, 503);
  }
});
