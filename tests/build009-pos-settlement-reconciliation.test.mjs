import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const sql = await readFile(new URL("../supabase/migrations/20261105001110_build009_pos_settlement_reconciliation.sql", import.meta.url), "utf8");

test("settlement schema covers provider batches, balance lines, reconciliation runs, matches, exceptions, bank deposits, approvals, cash closings and audit", () => {
 for (const table of ["mme_pos_settlement_batches","mme_pos_settlement_lines","mme_pos_reconciliation_runs","mme_pos_settlement_matches","mme_pos_settlement_exceptions","mme_pos_bank_deposits","mme_pos_settlement_bank_matches","mme_pos_settlement_approvals","mme_pos_cash_drawer_closings","mme_pos_settlement_audit_events"]) {
  assert.match(sql,new RegExp("create table public\\."+table));
  assert.match(sql,new RegExp("alter table public\\."+table+" enable row level security"));
 }
});
test("provider settlement import identity is idempotent and financial amounts use minor units", () => {
 assert.match(sql,/unique\(provider,provider_payout_reference\)/);
 assert.match(sql,/gross_amount_minor/);
 assert.match(sql,/fee_amount_minor/);
 assert.match(sql,/net_amount_minor/);
 assert.match(sql,/check\(gross_amount_minor-fee_amount_minor=net_amount_minor\)/);
});
test("settlement matches are scoped to the reconciliation batch and flag duplicate or mismatched records", () => {
 assert.match(sql,/v_line\.batch_id<>v_run\.batch_id/);
 assert.match(sql,/v_status:='duplicate'/);
 assert.match(sql,/v_status:='mismatch'/);
 assert.match(sql,/settlement_line_id/);
});
test("completion counts unmatched provider lines and unresolved exceptions", () => {
 assert.match(sql,/v_unmatched/);
 assert.match(sql,/v_open_exceptions/);
 assert.match(sql,/not exists\(select 1 from public\.mme_pos_settlement_matches/);
});
test("settlement approval is independent and cannot bypass unmatched lines or open exceptions", () => {
 assert.match(sql,/v_run\.created_by_person_id=p_approver_person_id/);
 assert.match(sql,/Unmatched lines or unresolved exceptions prevent settlement approval/);
 assert.match(sql,/p_decision not in \('approve','reject','return_for_review'\)/);
});
test("cash close enforces expected cash arithmetic and independent witness", () => {
 assert.match(sql,/expected_cash_minor bigint generated always as/);
 assert.match(sql,/counted_by_person_id<>witnessed_by_person_id/);
 assert.match(sql,/approved_by_person_id<>counted_by_person_id/);
});
test("shared identity gate contains settlement permissions and inherited employment and freeze controls", () => {
 for (const p of ["pos.settlement.view","pos.settlement.reconcile","pos.settlement.exception.manage","pos.settlement.approve","pos.settlement.bank.match","pos.settlement.cash.manage"]) assert.ok(sql.includes("'" + p + "'"));
 assert.match(sql,/employee_access_frozen/);
 assert.match(sql,/employment_status/);
 assert.match(sql,/scope->>'location_id'/);
});
test("direct client table access and RPC execution are restricted to trusted service role", () => {
 assert.match(sql,/from public,anon,authenticated/);
 assert.match(sql,/to service_role/);
 assert.match(sql,/revoke all on function public\.mme_pos_approve_settlement_run/);
});
test("settlement foundation does not initiate transfers or change bank balances", () => {
 assert.doesNotMatch(sql,/create or replace function[^;]*(wire_transfer|ach_debit|initiate_payout)/is);
});
