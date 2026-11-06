import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../supabase/functions/checkout-recovery-worker/index.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/migrations/20261103006700_build001_checkout_failure_recovery.sql", import.meta.url), "utf8");
const webhook = await readFile(new URL("../supabase/functions/stripe-webhook/index.ts", import.meta.url), "utf8");
const config = await readFile(new URL("../supabase/config.toml", import.meta.url), "utf8");

test("recovery worker uses dedicated secret authentication and explicit Stripe mode", () => {
  assert.match(worker, /MME_CHECKOUT_RECOVERY_SECRET/);
  assert.match(worker, /safeEqual\(suppliedSecret, expectedSecret\)/);
  assert.match(worker, /expectedSecret\.length < 32/);
  assert.match(worker, /STRIPE_LIVEMODE/);
  assert.match(config, /\[functions\.checkout-recovery-worker\][\s\S]*verify_jwt = false/);
});

test("worker reconciles missing database binding against Stripe order metadata", () => {
  assert.match(worker, /paymentIntents\.search/);
  assert.match(worker, /metadata\['mme_order_id'\]/);
  assert.match(worker, /mme_bind_order_payment_intent/);
  assert.match(worker, /matching\.length === 1/);
  assert.match(worker, /Multiple Stripe PaymentIntents match this order/);
});

test("worker never releases stock while payment is succeeded, unresolved, or cancellation fails", () => {
  assert.match(worker, /intent\.status === "succeeded"/);
  assert.match(worker, /payment_succeeded_after_reservation_expiry/);
  assert.match(worker, /payment_intent_status_unresolved/);
  assert.match(worker, /payment_intent_cancel_failed/);
  assert.match(worker, /stripe\.paymentIntents\.cancel/);
  assert.match(worker, /intent\.status !== "canceled"/);
  assert.match(worker, /mme_expire_single_inventory_reservation/);
});

test("recovery case ledger is private, durable, and uniquely tracked per order and case type", () => {
  assert.match(migration, /mme_checkout_recovery_cases/);
  assert.match(migration, /unique\(order_id,case_type\)/);
  assert.match(migration, /enable row level security/);
  assert.match(migration, /revoke all on public\.mme_checkout_recovery_cases from public,anon,authenticated/);
});

test("single-order expiry requires an active due reservation and pending order", () => {
  assert.match(migration, /v_order\.status<>'pending_payment'/);
  assert.match(migration, /v_res\.status<>'active' or v_res\.expires_at>now\(\)/);
  assert.match(migration, /mme_release_serialized_order_reservation/);
  assert.match(migration, /mme_release_order_reservation/);
});

test("Stripe webhook remains signature-verified and delegates event idempotency to database processor", () => {
  assert.match(webhook, /verifyStripeWebhook\(rawBody, signature, webhookSecret, stripeSecret\)/);
  assert.match(webhook, /mme_process_unified_order_payment_event/);
  assert.match(webhook, /p_provider_event_id: event\.id/);
});
