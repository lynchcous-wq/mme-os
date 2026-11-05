import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261105000920_build009_pos_tender_dispatch_worker.sql", import.meta.url), "utf8");

test("Tender worker claims with bounded leases and SKIP LOCKED", () => {
  assert.match(migration, /for update skip locked/i);
  assert.match(migration, /p_lease_seconds < 15 or p_lease_seconds > 600/);
  assert.match(migration, /lease_token = gen_random_uuid\(\)/);
  assert.match(migration, /lease_expires_at = now\(\) \+ make_interval/);
});

test("Tender worker retries with bounded exponential backoff and dead letters", () => {
  assert.match(migration, /attempts >= 8 then 'dead_letter'/);
  assert.match(migration, /least\(3600, 15 \* \(2 \^ least\(attempts, 7\)\)/);
  assert.match(migration, /max_attempts_exceeded/);
});

test("Trusted outcomes require the current unexpired lease", () => {
  assert.match(migration, /lease_token is distinct from p_lease_token/);
  assert.match(migration, /lease_expires_at is null or v_outbox\.lease_expires_at < now\(\)/);
  assert.match(migration, /unknown_reconciliation/);
  assert.match(migration, /manual_review/);
});

test("Tender worker records outcomes without exposing worker RPCs to user roles", () => {
  assert.match(migration, /revoke all on function public\.mme_pos_claim_tender_dispatch[\s\S]*from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.mme_pos_claim_tender_dispatch[\s\S]*to service_role/);
  assert.match(migration, /mme_pos_finish_tender_dispatch/);
  assert.match(migration, /mme_pos_retry_tender_dispatch/);
});

test("Provider operation references and captured amounts are validated", () => {
  assert.match(migration, /Provider operation reference is already assigned/);
  assert.match(migration, /p_provider_payment_reference is null[\s\S]*p_provider_operation_reference is null/);
  assert.match(migration, /p_captured_amount_minor > p_authorized_amount_minor/);
  assert.match(migration, /v_attempt\.operation <> 'sale'/);
});
