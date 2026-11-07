import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261107009700_build010_order_refund_reconciliation.sql", import.meta.url), "utf8");
const webhook = await readFile(new URL("../app/api/webhooks/stripe/order-refunds/route.ts", import.meta.url), "utf8");
const checkoutWebhook = await readFile(new URL("../app/api/webhooks/stripe/checkout/route.ts", import.meta.url), "utf8");

test("online-order refunds are separate from POS tender refund ledgers", () => {
  assert.match(migration, /mme_order_refund_requests/);
  assert.match(migration, /mme_order_refund_events/);
  assert.doesNotMatch(migration, /mme_pos_refund_requests/);
});

test("refund requests require paid Stripe-backed orders and independent approval", () => {
  assert.match(migration, /v_order\.status not in \('paid','partially_refunded'\)/);
  assert.match(migration, /v_order\.stripe_payment_intent_id is null/);
  assert.match(migration, /v_reserved \+ p_amount_cents > v_order\.total_cents/);
  assert.match(migration, /p_approver_id=v_request\.requested_by/);
  assert.match(migration, /status=case when p_approve then 'approved' else 'rejected' end/);
});

test("refund reconciliation validates request, order, PaymentIntent, amount and refund ID", () => {
  assert.match(migration, /v_request\.order_id is distinct from p_order_id/);
  assert.match(migration, /v_order\.stripe_payment_intent_id is distinct from p_payment_intent_id/);
  assert.match(migration, /v_request\.amount_cents<>p_amount_cents/);
  assert.match(migration, /v_request\.stripe_refund_id is distinct from p_provider_refund_id/);
  assert.match(migration, /v_request_found boolean/);
});

test("successful partial and full refunds update order state from reconciled totals", () => {
  assert.match(migration, /sum\(amount_cents\).*status='succeeded'/s);
  assert.match(migration, /'refunded' else 'partially_refunded'/);
  assert.match(migration, /provider_refund_succeeded/);
});

test("refund webhook verifies Stripe signature, replay window and test mode", () => {
  assert.match(webhook, /stripe-signature/);
  assert.match(webhook, /timingSafeEqual/);
  assert.match(webhook, /> 300/);
  assert.match(webhook, /event\.livemode !== false/);
  assert.match(webhook, /mme_reconcile_order_stripe_refund/);
  assert.match(webhook, /mme_refund_request_id/);
});

test("existing payment confirmation remains separate and intact", () => {
  assert.match(checkoutWebhook, /mme_confirm_stripe_order_payment/);
});
