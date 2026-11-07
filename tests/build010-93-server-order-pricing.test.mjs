import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/orders/create/route.ts", import.meta.url), "utf8");
const schema = await readFile(new URL("../supabase/migrations/20261107009300_build010_store_pickup_tax_destination.sql", import.meta.url), "utf8");
const checkout = await readFile(new URL("../app/api/checkout/session/route.ts", import.meta.url), "utf8");

test("order creation requires same-origin authenticated customer and idempotency key", () => {
  assert.match(route, /hasSameOrigin\(request\)/);
  assert.match(route, /requireBrowserUser\(request\)/);
  assert.match(route, /mme_customer_account_links/);
  assert.match(route, /mme_person_identities/);
  assert.match(route, /idempotency-key/);
});

test("only pickup is enabled and destination comes from active store record", () => {
  assert.match(route, /body\.fulfillment_method !== "pickup"/);
  assert.match(route, /mme_store_locations/);
  assert.match(route, /address_line1/);
  assert.match(schema, /add column if not exists address_line1/);
  assert.match(schema, /add column if not exists postal_code/);
});

test("prices are read from the database and serialized units fail closed", () => {
  assert.match(route, /mme_products/);
  assert.match(route, /product\.serialized/);
  assert.match(route, /product\.unit_price_cents/);
  assert.doesNotMatch(route, /body\.unit_price|body\.price|body\.subtotal|body\.tax_cents/);
});

test("tax is calculated by configured server-side provider and never guessed", () => {
  assert.match(route, /MME_TAX_CALCULATOR_URL/);
  assert.match(route, /MME_TAX_CALCULATOR_SECRET/);
  assert.match(route, /tax\.tax_cents/);
  assert.match(route, /Checkout is safely paused/);
});

test("order and stock reservation are created through one atomic RPC", () => {
  assert.match(route, /mme_create_order_and_reserve/);
  assert.match(route, /p_tax_cents: tax\.tax_cents/);
  assert.match(route, /p_discount_cents: 0/);
  assert.match(route, /p_expires_at/);
});

test("Stripe checkout expiry does not outlive the reservation", () => {
  assert.match(checkout, /Date\.now\(\) \/ 1000\) \+ 20 \* 60/);
});
