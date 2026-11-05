import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const sql = await readFile(new URL("../supabase/migrations/20261105001120_build009_pos_financial_close_exception_resolution.sql", import.meta.url), "utf8");

test("exception history, adjustment requests and close snapshots are protected by RLS", () => {
 for (const table of ["mme_pos_settlement_exception_history","mme_pos_settlement_adjustment_requests","mme_pos_financial_closes","mme_pos_financial_close_items","mme_pos_financial_close_events"]) {
  assert.match(sql,new RegExp("create table public\\."+table));
  assert.match(sql,new RegExp("alter table public\\."+table+" enable row level security"));
 }
 assert.match(sql,/from public,anon,authenticated/);
 assert.match(sql,/to service_role/);
});
test("exception assignment requires active, authorized assignee and store permission", () => {
 assert.match(sql,/mme_pos_assign_settlement_exception/);
 assert.match(sql,/pos\.settlement\.exception\.manage/);
 assert.match(sql,/p_assignee_person_id,'pos\.settlement\.exception\.manage'/);
 assert.match(sql,/assigned_to_person_id/);
});
test("exception resolution requires reason, evidence reference and audited history", () => {
 assert.match(sql,/p_resolution_notes/);
 assert.match(sql,/p_evidence_reference/);
 assert.match(sql,/mme_pos_settlement_exception_history/);
 assert.match(sql,/settlement_exception_/);
});
test("accepted variances require separate approver permission and cannot be self-accepted by assignee", () => {
 assert.match(sql,/p_accept_variance and \(p_actor_person_id=v_exception\.assigned_to_person_id/);
 assert.match(sql,/pos\.settlement\.approve/);
});
test("adjustments are requests, separately approved and never auto-posted", () => {
 assert.match(sql,/mme_pos_request_settlement_adjustment/);
 assert.match(sql,/mme_pos_review_settlement_adjustment/);
 assert.match(sql,/reviewed_by_person_id<>requested_by_person_id/);
 assert.match(sql,/posted_to_ledger/);
 assert.doesNotMatch(sql,/insert into public\.mme_pos_settlement_lines[\s\S]{0,1000}adjustment/i);
});
test("financial close is store, currency, period and business-timezone scoped", () => {
 assert.match(sql,/business_timezone text not null/);
 assert.match(sql,/pg_timezone_names/);
 assert.match(sql,/p_period_start at time zone p_business_timezone/);
 assert.match(sql,/unique\(location_id,business_period_start,business_period_end,currency\)/);
});
test("financial close blocks missing reconciliation, open exceptions, unmatched bank deposits and unresolved cash variances", () => {
 assert.match(sql,/unreconciled_batch_count/);
 assert.match(sql,/v_unreconciled/);
 assert.match(sql,/v_exceptions/);
 assert.match(sql,/v_unmatched_bank/);
 assert.match(sql,/v_cash_unapproved/);
 assert.match(sql,/v_cash_variances/);
 assert.match(sql,/v_processor_net=v_bank_net/);
});
test("a bank deposit cannot be matched to multiple settlement batches", () => {
 assert.match(sql,/unique index mme_pos_settlement_bank_match_one_batch_idx/);
 assert.match(sql,/where match_status='matched'/);
});
test("cash variance approval requires a documented reason", () => {
 assert.match(sql,/mme_pos_cash_close_variance_reason_check/);
 assert.match(sql,/variance_minor=0 or length\(btrim\(coalesce\(notes,''\)\)\)>=8/);
});
test("close approval and finalization are independent, reasoned and auditable", () => {
 assert.match(sql,/p_approver_person_id=v_close\.prepared_by_person_id/);
 assert.match(sql,/p_actor_person_id<>v_close\.approved_by_person_id/);
 assert.match(sql,/financial_close_events/);
 assert.match(sql,/reopen_reason/);
});
test("close preparation uses IANA timezone signature and old unsafe overload is revoked", () => {
 assert.match(sql,/mme_pos_prepare_financial_close\(uuid,timestamptz,timestamptz,text,text,uuid\)/);
 assert.match(sql,/revoke all on function public\.mme_pos_prepare_financial_close\(uuid,timestamptz,timestamptz,text,uuid\) from service_role/);
});
test("no money movement or processor mutation is implemented", () => {
 assert.doesNotMatch(sql,/create or replace function[^;]*(wire_transfer|ach_debit|initiate_payout|capture_payment)/is);
});
