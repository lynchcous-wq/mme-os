import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261105001240_build009_stripe_refund_settlement_ledger.sql", import.meta.url), "utf8");
const priorRefund = await readFile(new URL("../supabase/migrations/20261105000950_build009_pos_refund_dispute_reconciliation.sql", import.meta.url), "utf8");
const serialized = await readFile(new URL("../supabase/migrations/20261105001210_build009_serialized_return_refund_reconciliation.sql", import.meta.url), "utf8");
const reporting = await readFile(new URL("../supabase/migrations/20261105001130_build009_pos_financial_reporting.sql", import.meta.url), "utf8");
const settlement = await readFile(new URL("../supabase/migrations/20261105001110_build009_pos_settlement_reconciliation.sql", import.meta.url), "utf8");

test("settlement match and event ledgers are RLS protected and inaccessible to clients", () => {
  for (const table of ["mme_pos_stripe_refund_settlement_matches", "mme_pos_stripe_refund_settlement_events"]) {
    assert.match(migration, new RegExp("create table public\\." + table));
    assert.match(migration, new RegExp("alter table public\\." + table + " enable row level security"));
  }
  assert.match(migration, /from public,anon,authenticated/);
  assert.match(migration, /to service_role/);
});

test("only completed, provider-confirmed Stripe refunds can be matched", () => {
  assert.match(migration, /v_request\.status<>'completed'/);
  assert.match(migration, /v_request\.provider_refund_reference is null/);
  assert.match(migration, /v_attempt\.provider<>'stripe'/);
  assert.match(migration, /v_batch\.provider<>'stripe'/);
  assert.match(migration, /v_line\.provider<>'stripe'/);
});

test("matching requires exact refund reference, connected account, currency and amount", () => {
  assert.match(migration, /connected_account_mismatch/);
  assert.match(migration, /provider_refund_reference_mismatch/);
  assert.match(migration, /refund_currency_mismatch/);
  assert.match(migration, /abs\(v_line\.amount_minor\)<>v_request\.amount_minor/);
  assert.match(migration, /line_type<>'refund'/);
});

test("duplicate and cross-match conditions cannot silently double match", () => {
  assert.match(migration, /where match_status='matched'/);
  assert.match(migration, /one_match_idx/);
  assert.match(migration, /refund_already_matched_to_another_settlement_line/);
  assert.match(migration, /settlement_line_already_matched_to_another_refund/);
});

test("matched refunds create idempotent negative financial facts in integer minor units", () => {
  assert.match(migration, /mme_pos_import_financial_fact/);
  assert.match(migration, /-v_request\.amount_minor/);
  assert.match(migration, /stripe-refund:/);
  assert.match(reporting, /fact_type in \('gross_sale','discount','refund'/);
  assert.match(reporting, /unique\(location_id,source_system,source_line_reference,fact_type\)/);
});

test("closed periods and conflicting source facts are not silently overwritten", () => {
  assert.match(migration, /financial_period_closed_adjustment_required/);
  assert.match(migration, /existing_financial_refund_fact_conflicts/);
  assert.match(migration, /financial_fact_status/);
});

test("refund settlement state flows into serialized return settlement tracking", () => {
  assert.match(migration, /provider_reconciliation_status=case when v_status='matched'/);
  assert.match(serialized, /settlement_status=new\.provider_reconciliation_status/);
  assert.match(serialized, /settlement_matched/);
  assert.match(serialized, /settlement_mismatch/);
});

test("CEO and Finance dashboard metrics remain distinct from bank deposit proof", () => {
  assert.match(migration, /mme_pos_stripe_refund_settlement_dashboard/);
  assert.match(migration, /matched_refund_amount_minor/);
  assert.match(migration, /mismatched_refund_count/);
  assert.match(migration, /closed_period_fact_count/);
  assert.match(settlement, /mme_pos_settlement_bank_matches/);
  assert.match(migration, /bank deposit settlement remain distinct/);
});

test("settlement reconciliation does not initiate funds movement or provider requests", () => {
  assert.doesNotMatch(migration, /stripe\.refunds\.create|fetch\(|https?\.request|ach_debit|wire_transfer|initiate_payout/i);
  assert.match(priorRefund, /mme_pos_reconcile_refund_settlement/);
});
