import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261105001260_build009_stripe_financial_intelligence.sql", import.meta.url), "utf8");
const exceptions = await readFile(new URL("../supabase/migrations/20261105001250_build009_stripe_settlement_exception_intelligence.sql", import.meta.url), "utf8");
const settlement = await readFile(new URL("../supabase/migrations/20261105001110_build009_pos_settlement_reconciliation.sql", import.meta.url), "utf8");

test("financial intelligence snapshots, signals, recommendations and decisions are RLS protected", () => {
  for (const table of ["runs","signals","recommendations","decisions"]) {
    assert.match(migration, new RegExp("mme_pos_stripe_financial_intelligence_" + table));
  }
  assert.match(migration, /enable row level security/g);
  assert.match(migration, /from public,anon,authenticated/);
  assert.match(migration, /revoke update,delete,truncate/);
});

test("risk analysis is store-authorized, currency-scoped and reproducible", () => {
  assert.match(migration, /mme_pos_build_stripe_financial_intelligence/);
  assert.match(migration, /pos\.settlement\.exception\.manage/);
  assert.match(migration, /p_currency/);
  assert.match(migration, /explainable_rules_v1/);
  assert.match(migration, /baseline_start/);
  assert.match(migration, /baseline_end/);
});

test("risk scoring uses evidence from refund exceptions, settlement delays and exposure", () => {
  assert.match(migration, /mme_pos_stripe_settlement_exception_cases/);
  assert.match(migration, /mme_pos_settlement_batches/);
  assert.match(migration, /expected_arrival_at/);
  assert.match(migration, /unresolved_exposure_minor/);
  assert.match(migration, /delayed_settlement_count/);
  assert.match(migration, /risk_score between 0 and 100/);
});

test("signals retain observed values, baselines, explanations and evidence", () => {
  assert.match(migration, /mme_pos_stripe_financial_intelligence_signals/);
  assert.match(migration, /observed_value/);
  assert.match(migration, /baseline_value/);
  assert.match(migration, /explanation/);
  assert.match(migration, /evidence jsonb/);
});

test("recommendations are advisory and require documented human decisions", () => {
  assert.match(migration, /requires_human_approval boolean not null default true/);
  assert.match(migration, /mme_pos_record_stripe_financial_intelligence_decision/);
  assert.match(migration, /length\(btrim\(coalesce\(p_reason,''\)\)\)<8/);
  assert.match(migration, /Active employee assignee required/);
  assert.match(migration, /Critical recommendation requires settlement approval permission/);
});

test("risk engine does not create provider refunds, payouts or bank transfers", () => {
  assert.doesNotMatch(migration, /stripe\.refunds\.create|ach_debit|wire_transfer|initiate_payout|fetch\(/i);
  assert.match(migration, /do not initiate refunds, payouts, journal changes or bank transfers/i);
  assert.match(settlement, /mme_pos_settlement_bank_matches/);
  assert.match(exceptions, /mme_pos_stripe_settlement_exception_cases/);
});

test("CEO dashboard exposes latest risk snapshot by store and currency", () => {
  assert.match(migration, /mme_pos_stripe_financial_intelligence_dashboard/);
  assert.match(migration, /distinct on \(r\.location_id,r\.currency\)/);
  assert.match(migration, /risk_band/);
  assert.match(migration, /refund_exception_rate_bps/);
});
