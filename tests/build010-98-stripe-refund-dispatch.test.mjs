import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261107009700_build010_order_refund_reconciliation.sql", import.meta.url), "utf8");
const worker = await readFile(new URL("../app/api/cron/order-refund-dispatch/route.ts", import.meta.url), "utf8");
const api = await readFile(new URL("../app/api/employee/refunds/route.ts", import.meta.url), "utf8");
const page = await readFile(new URL("../app/employee/refunds/page.tsx", import.meta.url), "utf8");
const webhook = await readFile(new URL("../app/api/webhooks/stripe/order-refunds/route.ts", import.meta.url), "utf8");

test("refund dispatch claims use bounded leases, skip locked rows and bounded retries", () => {
  assert.match(migration, /for update skip locked/);
  assert.match(migration, /dispatch_lease_token/);
  assert.match(migration, /dispatch_lease_expires_at/);
  assert.match(migration, /dispatch_attempts<8/);
  assert.match(migration, /retry_scheduled/);
});

test("worker requires CRON_SECRET, Stripe test key and service role; uses Stripe idempotency", () => {
  assert.match(worker, /authorization/);
  assert.match(worker, /CRON_SECRET/);
  assert.match(worker, /startsWith\("sk_test_"\)/);
  assert.match(worker, /Idempotency-Key/);
  assert.match(worker, /metadata\[mme_order_id\]/);
  assert.match(worker, /metadata\[mme_refund_request_id\]/);
  assert.match(worker, /mme_finish_order_refund_dispatch/);
});

test("provider retries are limited to temporary errors; permanent errors go to review", () => {
  assert.match(worker, /response\.status === 429 \|\| response\.status >= 500/);
  assert.match(worker, /outcome = "manual_review"/);
  assert.match(migration, /status='manual_review'/);
});

test("employee refund center requires active employee permission and same-origin decisions", () => {
  assert.match(api, /requireBrowserUser/);
  assert.match(api, /hasSameOrigin/);
  assert.match(api, /orders\.refunds\.view/);
  assert.match(api, /mme_decide_order_refund_authorized/);
  assert.match(migration, /orders\.refunds\.approve/);
  assert.match(migration, /p_submitter_user_id=p_actor_user_id/);
  assert.match(migration, /employee_permission_grants/);
});

test("requester cannot approve own refund; approval reason is mandatory", () => {
  assert.match(migration, /p_approver_id=v_request\.requested_by/);
  assert.match(api, /body\.reason\.trim\(\)\.length < 2/);
  assert.match(page, /Decision reason/);
  assert.match(page, /Approve refund/);
  assert.match(page, /Reject/);
});

test("refund webhook remains signature-verified and is wired to reconciliation", () => {
  assert.match(webhook, /timingSafeEqual/);
  assert.match(webhook, /stripe-signature/);
  assert.match(webhook, /mme_reconcile_order_stripe_refund/);
});
