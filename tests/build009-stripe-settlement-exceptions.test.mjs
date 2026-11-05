import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261105001250_build009_stripe_settlement_exception_intelligence.sql", import.meta.url), "utf8");
const settlement = await readFile(new URL("../supabase/migrations/20261105001110_build009_pos_settlement_reconciliation.sql", import.meta.url), "utf8");
const refund = await readFile(new URL("../supabase/migrations/20261105001240_build009_stripe_refund_settlement_ledger.sql", import.meta.url), "utf8");

test("exception case and event records are RLS protected and service-role only", () => {
  assert.match(migration, /enable row level security/g);
  assert.match(migration, /from public,anon,authenticated/);
  assert.match(migration, /to service_role/);
});

test("detection is store-authorized and bounded to a specific batch", () => {
  assert.match(migration, /mme_pos_detect_stripe_settlement_exceptions/);
  assert.match(migration, /p_batch_id uuid/);
  assert.match(migration, /pos\.settlement\.exception\.manage/);
  assert.match(migration, /p_missing_refund_grace/);
  assert.match(migration, /interval '30 days'/);
});

test("missing processor refunds and processor refunds without internal requests are detected", () => {
  assert.match(migration, /missing_processor_refund/);
  assert.match(migration, /missing_internal_refund/);
  assert.match(migration, /completed_internal_refund_missing_from_settlement/);
  assert.match(migration, /processor_refund_without_internal_refund/);
});

test("mismatch and financial close conflicts create prioritized exception cases", () => {
  for (const type of ["amount_mismatch","currency_mismatch","connected_account_mismatch","duplicate_refund","closed_period","financial_fact_conflict"]) {
    assert.ok(migration.includes("'" + type + "'"));
  }
  assert.match(migration, /'critical'/);
  assert.match(migration, /'high'/);
});

test("exception lifecycle requires active assignee and evidence-backed resolution", () => {
  assert.match(migration, /employee_relationships/);
  assert.match(migration, /lifecycle_status='active'/);
  assert.match(migration, /resolution_code and evidence notes are required/);
  assert.match(migration, /pos\.settlement\.approve/);
});

test("SLA escalation is explicit, auditable and bounded", () => {
  assert.match(migration, /mme_pos_escalate_stripe_settlement_exceptions/);
  assert.match(migration, /due_at<=now\(\)/);
  assert.match(migration, /least\(escalation_level\+1,3\)/);
  assert.match(migration, /exception_sla_breached/);
});

test("dashboard reports outstanding exposure and overdue/unassigned work by currency", () => {
  assert.match(migration, /mme_pos_stripe_settlement_exception_dashboard/);
  assert.match(migration, /exposure_amount_minor/);
  assert.match(migration, /overdue_count/);
  assert.match(migration, /unassigned_count/);
  assert.match(migration, /group by location_id,currency,status,severity,exception_type/);
});

test("no automated money movement or silent source mutation is introduced", () => {
  assert.doesNotMatch(migration, /stripe\.refunds\.create|ach_debit|wire_transfer|initiate_payout|update public\.mme_pos_financial_reporting_facts/i);
  assert.match(refund, /financial_fact_status/);
  assert.match(settlement, /mme_pos_settlement_exceptions/);
});
