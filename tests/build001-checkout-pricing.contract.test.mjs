import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const pricing = await readFile(new URL("../supabase/functions/checkout-pricing/index.ts", import.meta.url), "utf8");
const payment = await readFile(new URL("../supabase/functions/create-checkout-payment/index.ts", import.meta.url), "utf8");
const config = await readFile(new URL("../supabase/config.toml", import.meta.url), "utf8");

test("pricing endpoint uses dedicated constant-time internal secret authentication", () => {
  assert.match(pricing, /MME_CHECKOUT_PRICING_SECRET/);
  assert.match(pricing, /safeEqual\(suppliedSecret, expectedSecret\)/);
  assert.match(pricing, /expectedSecret\.length < 32/);
  assert.match(config, /\[functions\.checkout-pricing\][\s\S]*verify_jwt = false/);
});

test("pricing requires active identity security and customer relationship", () => {
  assert.match(pricing, /mme_person_identities/);
  assert.match(pricing, /security_status !== "active"/);
  assert.match(pricing, /mme_customer_relationships/);
  assert.match(pricing, /customer\.status !== "active"/);
});

test("pricing requires explicitly linked published catalog products and active commerce records", () => {
  assert.match(pricing, /catalog_product_id/);
  assert.match(pricing, /catalog_status/);
  assert.match(pricing, /eq\("published"\)/);
  assert.match(pricing, /eq\("active", true\)/);
});

test("pricing validates live stock and exact serialized device identity", () => {
  assert.match(pricing, /mme_inventory_balances/);
  assert.match(pricing, /mme_serialized_units/);
  assert.match(pricing, /unit\.product_id !== line\.product_id/);
  assert.match(pricing, /unit\.location_id !== line\.location_id/);
  assert.match(pricing, /line\.quantity !== 1/);
});

test("pickup and shipping require complete fulfillment details and active location", () => {
  assert.match(pricing, /pickup_location_inventory_mismatch/);
  assert.match(pricing, /complete_shipping_address_required/);
  assert.match(pricing, /mme_store_locations/);
});

test("tax, shipping and discounts fail closed through a bounded HTTPS quote adapter", () => {
  assert.match(pricing, /url\.protocol !== "https:"/);
  assert.match(pricing, /MME_CHECKOUT_QUOTE_URL/);
  assert.match(pricing, /MME_CHECKOUT_QUOTE_SECRET/);
  assert.match(pricing, /AbortSignal\.timeout\(8000\)/);
  assert.match(pricing, /tax_shipping_discount_quote_unavailable/);
  assert.match(pricing, /discount_reference/);
});

test("checkout verifies quote subtotal still matches the atomic database order snapshot", () => {
  assert.match(payment, /expected_subtotal_cents/);
  assert.match(payment, /order\.subtotal_cents !== priced\.expected_subtotal_cents/);
  assert.match(payment, /AbortSignal\.timeout\(10_000\)/);
});

test("checkout remains disabled when trusted pricing is unavailable", () => {
  assert.match(payment, /MME_CHECKOUT_PRICING_URL/);
  assert.match(payment, /MME_CHECKOUT_PRICING_SECRET/);
  assert.match(payment, /trusted_pricing_unavailable/);
});
