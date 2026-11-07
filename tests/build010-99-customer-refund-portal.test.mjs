import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const api = await readFile(new URL("../app/api/account/refunds/route.ts", import.meta.url), "utf8");
const page = await readFile(new URL("../app/account/refunds/page.tsx", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/migrations/20261107009700_build010_order_refund_reconciliation.sql", import.meta.url), "utf8");
const checkout = await readFile(new URL("../app/api/checkout/session/route.ts", import.meta.url), "utf8");

test("customer refund API requires same-origin authenticated active customer identity", () => {
  assert.match(api, /hasSameOrigin/);
  assert.match(api, /requireBrowserUser/);
  assert.match(api, /mme_customer_account_links/);
  assert.match(api, /mme_person_identities/);
  assert.match(api, /lifecycle_status=eq\.active/);
});

test("customer can only request refund for their own paid Stripe-backed order", () => {
  assert.match(api, /customer_identity_id=eq\./);
  assert.match(api, /Only completed Stripe-paid orders/);
  assert.match(api, /stripe_payment_intent_id/);
  assert.match(api, /mme_request_order_refund/);
  assert.match(api, /p_requested_by: session\.user\.id/);
});

test("refund request idempotency is scoped to authenticated customer", () => {
  assert.match(api, /cust-" \+ session\.user\.id/);
  assert.match(api, /idempotencyKey/);
  assert.match(migration, /idempotency_key text not null unique/);
});

test("refund amount cap includes concurrent pending, approved, processing and succeeded requests", () => {
  assert.match(migration, /status in \('requested','approved','processing','pending_provider','succeeded'\)/);
  assert.match(migration, /v_reserved \+ p_amount_cents > v_order\.total_cents/);
});

test("customer order and refund history queries are scoped to customer identity", () => {
  assert.match(api, /customer_identity_id=eq\./);
  assert.match(api, /mme_order_refund_requests\?order_id=in\./);
  assert.match(api, /Cache-Control.*no-store/);
});

test("portal displays review, processing, success and exception states", () => {
  assert.match(page, /Awaiting MME review/);
  assert.match(page, /Stripe confirmed this refund/);
  assert.match(page, /manual_review/);
  assert.match(page, /Submit refund request/);
  assert.match(page, /Order history/);
});

test("portal does not claim a request is an issued refund", () => {
  assert.match(page, /does not guarantee approval/);
  assert.match(page, /not yet approved or refunded/);
});

test("existing checkout ownership check remains in place", () => {
  assert.match(checkout, /customer_identity_id=eq\./);
});
