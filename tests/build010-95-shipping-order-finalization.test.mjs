import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const order = await readFile(new URL("../app/api/orders/create/route.ts", import.meta.url), "utf8");
const quote = await readFile(new URL("../app/api/shipping/quotes/route.ts", import.meta.url), "utf8");
const schema = await readFile(new URL("../supabase/migrations/20261103000600_build001_inventory_orders.sql", import.meta.url), "utf8");

test("order finalization authenticates same-origin customer and validates idempotency", () => {
  assert.match(order, /hasSameOrigin\(request\)/);
  assert.match(order, /requireBrowserUser\(request\)/);
  assert.match(order, /idempotency-key/);
  assert.match(order, /mme_customer_account_links/);
  assert.match(order, /mme_person_identities/);
});

test("shipping quote token signature, customer, expiry, and cart are verified", () => {
  assert.match(order, /MME_SHIPPING_QUOTE_SIGNING_SECRET/);
  assert.match(order, /createHmac\("sha256"/);
  assert.match(order, /timingSafeEqual/);
  assert.match(order, /claims\.customer_id !== customerId/);
  assert.match(order, /claims\.expires_at <= Date\.now\(\)/);
  assert.match(order, /claims\.cart_fingerprint !== fingerprint/);
  assert.match(quote, /cart_fingerprint: cartFingerprint/);
});

test("shipping uses verified destination and server-quoted fulfillment amount", () => {
  assert.match(order, /carrier_quote_id: claims\.quote_id/);
  assert.match(order, /carrier_rate_id: claims\.rate_id/);
  assert.match(order, /fulfillmentCents = claims\.amount_cents/);
  assert.match(order, /MME_SHIPPING_INVENTORY_LOCATION_ID/);
  assert.match(order, /MME_TAX_CALCULATOR_URL/);
});

test("both fulfillment methods use atomic order and inventory reservation RPC", () => {
  assert.match(order, /mme_create_order_and_reserve/);
  assert.match(order, /p_fulfillment_method: method/);
  assert.match(order, /p_fulfillment_cents: fulfillmentCents/);
  assert.match(schema, /perform public\.mme_reserve_inventory\(v_order_id, p_items, p_expires_at\)/);
  assert.match(schema, /p_fulfillment_method not in \('pickup','shipping'\)/);
});

test("order pricing is sourced from the database and serialized units are blocked", () => {
  assert.match(order, /unit_price_cents/);
  assert.match(order, /product\.serialized/);
  assert.doesNotMatch(order, /body\.unit_price|body\.price|body\.tax_cents|body\.shipping_amount/);
});

test("shipping order does not trust a client-submitted carrier amount", () => {
  assert.match(order, /shipping_quote_token/);
  assert.doesNotMatch(order, /body\.shipping_cents|body\.shipping_amount_cents/);
});
