import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const webhook = await readFile(new URL("supabase/functions/stripe-webhook/index.ts", root), "utf8");
const worker = await readFile(new URL("supabase/functions/customer-notification-worker/index.ts", root), "utf8");
const finalizer = await readFile(new URL("supabase/migrations/20261103006800_build001_paid_order_confirmation_and_customer_history.sql", root), "utf8");
const notificationMigration = await readFile(new URL("supabase/migrations/20261103006900_build001_fulfillment_status_notification_automation.sql", root), "utf8");
const account = await readFile(new URL("app/account/page.tsx", root), "utf8");
const config = await readFile(new URL("supabase/config.toml", root), "utf8");

test("only verified paid Stripe orders initialize fulfillment; duplicate webhook retries can finish finalization", () => {
  assert.match(webhook, /verifyStripeWebhook\(rawBody, signature, webhookSecret, stripeSecret\)/);
  assert.match(webhook, /mme_process_unified_order_payment_event/);
  assert.match(webhook, /mme_finalize_paid_order_fulfillment/);
  assert.match(webhook, /currentOrder\?\.status === "paid"/);
  assert.match(finalizer, /v_order\.status not in \('paid','partially_refunded'\)/);
});

test("paid-order finalizer creates shipping or pickup fulfillment and queues one email", () => {
  assert.match(finalizer, /mme_create_order_fulfillment/);
  assert.match(finalizer, /mme_queue_fulfillment_notification/);
  assert.match(finalizer, /order-paid:/);
  assert.match(finalizer, /mme_get_my_order_history/);
});

test("fulfillment transitions automatically enqueue idempotent customer email", () => {
  assert.match(notificationMigration, /after update of fulfillment_status/);
  assert.match(notificationMigration, /mme_queue_fulfillment_notification/);
  assert.match(notificationMigration, /order_shipped/);
  assert.match(notificationMigration, /pickup_ready/);
  assert.match(notificationMigration, /order_delivered/);
});

test("notification worker authenticates, uses leased queue, Resend idempotency and bounded retry", () => {
  assert.match(worker, /MME_CUSTOMER_NOTIFICATION_SECRET/);
  assert.match(worker, /safeEqual\(secret, supplied\)/);
  assert.match(worker, /mme_claim_customer_notifications/);
  assert.match(worker, /https:\/\/api\.resend\.com\/emails/);
  assert.match(worker, /Idempotency-Key/);
  assert.match(worker, /mme_complete_customer_notification/);
  assert.match(worker, /mme_fail_customer_notification/);
  assert.match(config, /\[functions\.customer-notification-worker\][\s\S]*verify_jwt = false/);
});

test("customer account requests only the authenticated caller's own order history", () => {
  assert.match(account, /mme_get_my_order_history/);
  assert.match(account, /signInWithOtp/);
  assert.match(account, /shouldCreateUser: false/);
  assert.match(account, /tracking_url/);
  assert.match(account, /pickup_ready_at/);
});
