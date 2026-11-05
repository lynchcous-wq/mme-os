import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261105000930_build009_pos_reconciliation.sql", import.meta.url), "utf8");

test("Settlement imports are provider/account scoped and idempotent", () => {
  assert.match(migration, /unique\(provider, provider_account_reference, provider_record_reference\)/);
  assert.match(migration, /return query select v_id, true/);
  assert.match(migration, /p_raw_record_digest !~ '\^\[a-fA-F0-9\]\{64\}\$'/);
});

test("Reconciliation requires provider references and identifies ambiguous matches", () => {
  assert.match(migration, /provider_operation_reference = v_record\.provider_operation_reference/);
  assert.match(migration, /provider_payment_reference = v_record\.provider_payment_reference/);
  assert.match(migration, /ambiguous_tender_reference/);
  assert.match(migration, /no_tender_reference_match/);
});

test("Reconciliation compares currency, capture and refund amounts", () => {
  assert.match(migration, /currency_mismatch/);
  assert.match(migration, /capture_amount_mismatch/);
  assert.match(migration, /refund_amount_mismatch/);
  assert.match(migration, /tender_state_mismatch/);
});

test("Duplicates and policy-sensitive settlement records are not silently matched", () => {
  assert.match(migration, /duplicate_provider_operation_record/);
  assert.match(migration, /record_type_requires_policy_review/);
  assert.match(migration, /manual_review/);
});

test("Reconciliation records auditable outcomes and limits RPC access", () => {
  assert.match(migration, /create table public\.mme_pos_reconciliation_events/);
  assert.match(migration, /insert into public\.mme_pos_reconciliation_events/);
  assert.match(migration, /revoke all on function public\.mme_pos_reconcile_settlement_record[\s\S]*from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.mme_pos_reconcile_settlement_record[\s\S]*to service_role/);
});
