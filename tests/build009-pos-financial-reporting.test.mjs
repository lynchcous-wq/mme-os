import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const sql = await readFile(new URL("../supabase/migrations/20261105001130_build009_pos_financial_reporting.sql", import.meta.url), "utf8");

test("reporting facts, runs, grouped rows and summaries are RLS protected", () => {
 for (const table of ["mme_pos_financial_reporting_facts","mme_pos_financial_report_runs","mme_pos_financial_report_rows","mme_pos_financial_report_summaries"]) {
  assert.match(sql,new RegExp("create table public\\."+table));
  assert.match(sql,new RegExp("alter table public\\."+table+" enable row level security"));
 }
 assert.match(sql,/from public,anon,authenticated/);
});
test("financial fact import requires reporting permission, store scope and IANA business date", () => {
 assert.match(sql,/pos\.finance\.report\.import/);
 assert.match(sql,/p_occurred_at at time zone p_business_timezone/);
 assert.match(sql,/p_business_date/);
 assert.match(sql,/pg_timezone_names/);
});
test("source imports are idempotent and conflicting duplicate references are quarantined", () => {
 assert.match(sql,/unique\(location_id,source_system,source_line_reference,fact_type\)/);
 assert.match(sql,/Source reference already exists with conflicting financial content/);
});
test("fact types and signed integer minor-unit amounts are constrained", () => {
 assert.match(sql,/amount_minor bigint not null/);
 assert.match(sql,/fact_type in \('gross_sale','discount','refund','subscription_revenue'/);
 assert.match(sql,/amount_minor<=0/);
});
test("closed periods reject additional financial facts", () => {
 assert.match(sql,/Financial facts cannot be added to a closed period/);
 assert.match(sql,/c\.status='closed'/);
});
test("report builds are scoped to one store, currency, date range and source cutoff", () => {
 assert.match(sql,/pos\.finance\.report\.build/);
 assert.match(sql,/source_cutoff_at/);
 assert.match(sql,/f\.location_id=p_location_id and f\.currency=p_currency/);
 assert.match(sql,/f\.business_date between p_period_start and p_period_end/);
});
test("reports include daily store, category, register and employee profitability aggregates", () => {
 for (const level of ["store","product_category","register","employee"]) assert.ok(sql.includes("'"+level+"'"));
 assert.match(sql,/gross_profit_minor/);
 assert.match(sql,/contribution_profit_minor/);
 assert.match(sql,/gross_margin_basis_points/);
});
test("report snapshots and source facts cannot be updated or deleted", () => {
 assert.match(sql,/create trigger mme_pos_financial_facts_immutable before update or delete/);
 assert.match(sql,/create trigger mme_pos_financial_report_runs_immutable before update or delete/);
 assert.match(sql,/revoke update,delete,truncate on public\.mme_pos_financial_reporting_facts/);
});
test("settlement and cash summaries are explicitly separate from sales revenue", () => {
 assert.match(sql,/settlement_net_minor/);
 assert.match(sql,/matched_bank_deposit_minor/);
 assert.match(sql,/cash_expected_minor/);
 assert.match(sql,/open_settlement_exception_count/);
});
test("forecasts are labeled illustrative, seven-day, weekday baselines and require at least four observations", () => {
 assert.match(sql,/illustrative_projection/);
 assert.match(sql,/weekday_28_day_baseline_v1/);
 assert.match(sql,/p_as_of_date\+7/);
 assert.match(sql,/w\.observations>=4/);
});
test("forecast and report builders never initiate payments or mutate processor balances", () => {
 assert.doesNotMatch(sql,/initiate_payout|ach_debit|wire_transfer|capture_payment/i);
});
