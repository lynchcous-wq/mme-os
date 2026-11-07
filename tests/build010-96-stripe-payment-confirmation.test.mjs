import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const checkout = await readFile(new URL("../app/api/checkout/session/route.ts", import.meta.url), "utf8");
const webhook = await readFile(new URL("../app/api/webhooks/stripe/checkout/route.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/migrations/20261107009600_build010_stripe_payment_confirmation.sql", import.meta.url), "utf8");
const priorPaymentFlow = await readFile(new URL("../supabase/migrations/20261107009000_build010_order_payment_finalization.sql", import.meta.url), "utf8");

test("Checkout stays test-mode, customer-scoped, reservation-backed and idempotent", () => {
  assert.match(checkout, /sk_test_/);
  assert.match(checkout, /requireBrowserUser\(request\)/);
  assert.match(checkout, /mme_customer_account_links/);
  assert.match(checkout, /status !== "pending_payment"/);
  assert.match(checkout, /mme_inventory_reservations/);
  assert.match(checkout, /mme_bind_stripe_checkout_session/);
  assert.match(checkout, /Idempotency-Key/);
  assert.match(checkout, /30 \* 60/);
});

test("Stripe webhook verifies raw signature, timestamp tolerance and test mode", () => {
  assert.match(webhook, /request\.text\(\)/);
  assert.match(webhook, /createHmac\("sha256"/);
  assert.match(webhook, /timingSafeEqual/);
  assert.match(webhook, /> 300/);
  assert.match(webhook, /stripe-signature/);
  assert.match(webhook, /event\.livemode !== false/);
});

test("paid webhook binds event to customer, order, session, payment intent, amount and currency", () => {
  assert.match(webhook, /mme_confirm_stripe_order_payment/);
  assert.match(webhook, /mme_customer_identity_id/);
  assert.match(webhook, /client_reference_id/);
  assert.match(webhook, /payment_intent/);
  assert.match(migration, /stripe_checkout_session_id/);
  assert.match(migration, /stripe_payment_intent_id/);
  assert.match(migration, /v_order\.customer_identity_id is distinct from p_customer_identity_id/);
  assert.match(migration, /v_order\.stripe_checkout_session_id is distinct from p_checkout_session_id/);
  assert.match(migration, /v_order\.total_cents <> p_amount_cents/);
});

test("payment confirmation is idempotent and protects event payload integrity", () => {
  assert.match(migration, /unique index if not exists mme_orders_stripe_checkout_session_uidx/);
  assert.match(migration, /unique index if not exists mme_orders_stripe_payment_intent_uidx/);
  assert.match(migration, /on conflict \(provider, provider_event_id\) do nothing/);
  assert.match(migration, /Stripe event ID replayed with a different payload/);
});

test("paid order atomically consumes reservation; expired or inconsistent stock enters review", () => {
  assert.match(migration, /set on_hand_quantity = on_hand_quantity - v_line\.quantity/);
  assert.match(migration, /set status = 'consumed'/);
  assert.match(migration, /status = 'payment_review'/);
  assert.match(priorPaymentFlow, /async_payment_failed/);
  assert.match(priorPaymentFlow, /set reserved_quantity = reserved_quantity - v_line\.quantity/);
  assert.match(priorPaymentFlow, /payment_not_completed_reservation_released/);
});

test("checkout session is bound before customer receives the redirect URL", () => {
  assert.match(checkout, /mme_bind_stripe_checkout_session/);
  assert.match(checkout, /bound !== true/);
  assert.match(checkout, /\/expire/);
});
