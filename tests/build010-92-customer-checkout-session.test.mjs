import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/checkout/session/route.ts", import.meta.url), "utf8");

test("checkout requires same-origin request and authenticated customer session", () => {
  assert.match(route, /hasSameOrigin\(request\)/);
  assert.match(route, /requireBrowserUser\(request\)/);
  assert.match(route, /if \(!session\.user\)/);
});

test("checkout verifies exactly one active customer identity", () => {
  assert.match(route, /mme_customer_account_links/);
  assert.match(route, /link_status=eq\.active/);
  assert.match(route, /mme_person_identities/);
  assert.match(route, /lifecycle_status=eq\.active/);
  assert.match(route, /links\.length !== 1/);
});

test("checkout loads the order scoped to the signed-in customer", () => {
  assert.match(route, /customer_identity_id=eq\./);
  assert.match(route, /status !== "pending_payment"/);
  assert.match(route, /order\.currency !== "USD"/);
  assert.match(route, /Number\.isSafeInteger\(order\.total_cents\)/);
});

test("checkout requires an active unexpired inventory reservation", () => {
  assert.match(route, /mme_inventory_reservations/);
  assert.match(route, /status=eq\.active/);
  assert.match(route, /expires_at=gt\./);
});

test("Stripe Checkout uses server-side total, order metadata and an idempotency key", () => {
  assert.match(route, /api\.stripe\.com\/v1\/checkout\/sessions/);
  assert.match(route, /line_items\[0\]\[price_data\]\[unit_amount\]/);
  assert.match(route, /String\(order\.total_cents\)/);
  assert.match(route, /metadata\[mme_order_id\]/);
  assert.match(route, /Idempotency-Key/);
  assert.match(route, /mme-checkout-order-/);
});

test("checkout response is private and does not expose provider secrets", () => {
  assert.match(route, /Cache-Control.*no-store/);
  assert.doesNotMatch(route, /STRIPE_SECRET_KEY.*NextResponse\.json/);
});
