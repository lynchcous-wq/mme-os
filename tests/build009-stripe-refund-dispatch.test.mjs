import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/cron/stripe-refunds/route.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/migrations/20261105001220_build009_stripe_refund_adapter_webhook.sql", import.meta.url), "utf8");

test("refund worker is cron-authenticated and server-configured", () => {
  assert.match(route, /CRON_SECRET/);
  assert.match(route, /authorization/);
  assert.match(route, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(route, /STRIPE_SECRET_KEY/);
});

test("claims are provider-scoped and bounded", () => {
  assert.match(route, /mme_pos_claim_stripe_refund_dispatch/);
  assert.match(migration, /a\.provider='stripe'/);
  assert.match(route, /p_limit: 10/);
});

test("Stripe refund submission uses provider idempotency and connected account", () => {
  assert.match(route, /api\.stripe\.com\/v1\/refunds/);
  assert.match(route, /Idempotency-Key/);
  assert.match(route, /Stripe-Account/);
  assert.match(route, /payment_intent/);
});

test("synchronous provider response never marks refund completed", () => {
  assert.match(route, /unknown_reconciliation/);
  assert.match(route, /Webhook reconciliation is authoritative/);
  assert.doesNotMatch(route, /p_outcome:\s*["']succeeded/);
});

test("ambiguous transport and server outcomes require reconciliation", () => {
  assert.match(route, /STRIPE_NETWORK_OUTCOME_UNKNOWN/);
  assert.match(route, /STRIPE_OUTCOME_REQUIRES_RECONCILIATION/);
  assert.match(route, /status !== 429/);
});

test("worker does not log or return provider payloads or cardholder data", () => {
  assert.doesNotMatch(route, /console\.(log|error)/);
  assert.doesNotMatch(route, /cvv|cvc|pan|pin/i);
});
