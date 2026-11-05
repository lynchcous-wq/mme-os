import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261105000910_build009_pos_tender_attempt_ledger.sql", import.meta.url), "utf8");

test("Tender attempt ledger is separate from payment confirmation", () => {
  assert.match(migration, /status text not null default 'created'/);
  assert.match(migration, /not proof of authorization, capture, settlement or payment/i);
  assert.match(migration, /tender\.dispatch_requested/);
});

test("Tender attempts bind idempotency to transaction and request fingerprint", () => {
  assert.match(migration, /unique \(transaction_id, idempotency_key\)/);
  assert.match(migration, /request_fingerprint text not null/);
  assert.match(migration, /Tender idempotency key reused with different request/);
});

test("Tender creation checks employee permission, order currency and calculation snapshot", () => {
  assert.match(migration, /mme_person_authorize_pos_action\(p_actor_person_id, 'pos\.tender\.create'/);
  assert.match(migration, /v_tx\.currency <> p_currency/);
  assert.match(migration, /v_tx\.calculation_reference is distinct from p_calculation_reference/);
});

test("Tender ledger reserves balances safely and blocks overpayment", () => {
  assert.match(migration, /status in \('created','pending','authorized','unknown_reconciliation'\)/);
  assert.match(migration, /status in \('partially_captured','captured'\) then captured_amount_minor/);
  assert.match(migration, /Tender amount exceeds remaining transaction balance/);
});

test("Tender ledger is service-role-only with RLS and no raw card data columns", () => {
  assert.match(migration, /enable row level security/);
  assert.match(migration, /grant execute on function public\.mme_pos_create_tender_attempt[\s\S]*to service_role/);
  for (const field of ["pan", "card_number", "cvv", "cvc", "track_data"]) {
    assert.doesNotMatch(migration, new RegExp(`\\b${field}\\b`, "i"));
  }
});
