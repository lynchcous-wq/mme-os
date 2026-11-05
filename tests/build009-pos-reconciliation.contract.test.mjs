import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261105000930_build009_pos_reconciliation.sql", import.meta.url), "utf8");

test("Settlement imports are provider/account scoped and idempotent", () => {
  assert.ok(migration.includes("unique(provider, provider_account_reference, provider_record_reference)"));
  assert.ok(migration.includes("Provider record reference reused with different settlement data"));
  assert.ok(migration.includes("return query select v_existing.id, true"));
  assert.ok(migration.includes("p_raw_record_digest !~"));
});

test("Reconciliation requires provider references and identifies ambiguous matches", () => {
  assert.ok(migration.includes("provider_operation_reference = v_record.provider_operation_reference"));
  assert.ok(migration.includes("provider_payment_reference = v_record.provider_payment_reference"));
  assert.ok(migration.includes("ambiguous_tender_reference"));
  assert.ok(migration.includes("no_tender_reference_match"));
});

test("Reconciliation compares currency, capture and refund amounts", () => {
  for (const code of ["currency_mismatch", "capture_amount_mismatch", "refund_amount_mismatch", "tender_state_mismatch"]) {
    assert.ok(migration.includes(code));
  }
});

test("Duplicates and policy-sensitive settlement records are not silently matched", () => {
  assert.ok(migration.includes("duplicate_provider_operation_record"));
  assert.ok(migration.includes("x.record_type = v_record.record_type"));
  assert.ok(migration.includes("v_record.provider_operation_reference is not null"));
  assert.ok(migration.includes("record_type_requires_policy_review"));
  assert.ok(migration.includes("manual_review"));
});

test("Reconciliation records auditable outcomes and limits RPC access", () => {
  assert.ok(migration.includes("create table public.mme_pos_reconciliation_events"));
  assert.ok(migration.includes("insert into public.mme_pos_reconciliation_events"));
  assert.ok(migration.includes("revoke all on function public.mme_pos_reconcile_settlement_record"));
  assert.ok(migration.includes("grant execute on function public.mme_pos_reconcile_settlement_record"));
});
