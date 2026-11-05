import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const migration = await readFile(new URL("../supabase/migrations/20261105001220_build009_stripe_refund_adapter_webhook.sql", import.meta.url), "utf8");
const webhook = await readFile(new URL("../app/api/webhooks/stripe/refunds/route.ts", import.meta.url), "utf8");
const refundControls = await readFile(new URL("../supabase/migrations/20261105000940_build009_pos_refund_void_controls.sql", import.meta.url), "utf8");

test("Stripe claim worker is provider-scoped and bounded", () => {
  assert.match(migration, /mme_pos_claim_stripe_refund_dispatch/);
  assert.match(migration, /a\.provider='stripe'/);
  assert.match(migration, /p_limit>25/);
  assert.match(migration, /p_lease_seconds>300/);
});
test("webhook uses raw body signature validation and timestamp tolerance", () => {
  assert.match(webhook, /request\.arrayBuffer\(\)/);
  assert.match(webhook, /createHmac\("sha256"/);
  assert.match(webhook, /timingSafeEqual/);
  assert.match(webhook, /300/);
});
test("webhook rejects oversized payload and unsupported events", () => {
  assert.match(webhook, /262144/);
  assert.match(webhook, /refund\.created/);
  assert.match(webhook, /refund\.updated/);
});
test("verified event is bound to account, payment, refund, amount and currency", () => {
  for (const field of ["p_provider_account_reference", "p_provider_payment_reference", "p_provider_refund_reference", "p_amount_minor", "p_currency"]) assert.match(migration, new RegExp(field));
});
test("webhook event ID is unique and payload changes are rejected", () => {
  assert.match(migration, /provider_event_id text not null unique/);
  assert.match(migration, /payload_sha256<>p_payload_sha256/);
});
test("existing refund dispatcher enforces lease token and bounded attempts", () => {
  assert.match(refundControls, /v_request\.lease_token is distinct from p_lease_token/);
  assert.match(refundControls, /v_request\.lease_expires_at < now\(\)/);
  assert.match(refundControls, /attempts < 8/);
});
test("no cardholder primary account number, security code or PIN fields are added", () => {
  assert.doesNotMatch(migration, /\b(pan|cvv|cvc|pin)\b/i);
});
