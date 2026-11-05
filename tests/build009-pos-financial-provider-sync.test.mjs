import {normalizeStripeBalanceTransactions} from "../lib/pos/financial-adapters/stripe-balance-transactions.ts";
import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const migration=await readFile(new URL("../supabase/migrations/20261105001160_build009_pos_financial_provider_sync.sql",import.meta.url),"utf8");
const connectorMigration=await readFile(new URL("../supabase/migrations/20261105001140_build009_pos_financial_source_connectors.sql",import.meta.url),"utf8");
const adapter=await readFile(new URL("../lib/pos/financial-adapters/stripe-balance-transactions.ts",import.meta.url),"utf8");
const route=await readFile(new URL("../app/api/cron/pos-financial-provider-sync/route.ts",import.meta.url),"utf8");
const api=await readFile(new URL("../app/api/pos/financial-connectors/route.ts",import.meta.url),"utf8");
const page=await readFile(new URL("../app/internal/financial-connectors/page.tsx",import.meta.url),"utf8");
const config=JSON.parse(await readFile(new URL("../vercel.json",import.meta.url),"utf8"));

test("provider sync ledger is store-scoped, indexed and RLS protected",()=>{
 assert.match(migration,/mme_pos_financial_sync_runs/);
 assert.match(migration,/enable row level security/);
 assert.match(migration,/revoke all on public\.mme_pos_financial_sync_runs from public,anon,authenticated/);
 assert.match(migration,/unique index mme_pos_financial_sync_one_active_connector_idx/);
});
test("sync run creation requires active connector and authorized worker",()=>{
 assert.match(migration,/mme_pos_authorize_hardware_action/);
 assert.match(migration,/pos\.finance\.report\.import/);
 assert.match(migration,/STALE_RUN_RECOVERED/);
});
test("cursor is advanced only after successful page staging",()=>{
 assert.match(migration,/p_status in \('partial','completed'\)/);
 assert.match(migration,/mme_pos_financial_import_cursors/);
 assert.match(migration,/cursor_advanced/);
});
test("import staging stores fingerprint in the actual schema column",()=>{
 assert.match(connectorMigration,/row_fingerprint_md5 text not null/);
 assert.match(connectorMigration,/insert into public\.mme_pos_financial_import_rows\(batch_id,row_number,source_line_reference,fact_type,normalized_record,row_fingerprint_md5\)/);
 assert.match(connectorMigration,/v_digest:=md5\(v_record::text\)/);
 assert.doesNotMatch(connectorMigration,/normalized_record,row_digest_sha256/);
});
test("Stripe adapter fetches balance transactions with pagination and no-store credentials",()=>{
 assert.match(adapter,/\/v1\/balance_transactions/);
 assert.match(adapter,/created\[gte\]/);
 assert.match(adapter,/starting_after/);
 assert.match(adapter,/cache:"no-store"/);
});
test("Stripe normalizer maps sales, refunds, chargebacks and fees while ignoring unrelated balance movements",()=>{
 for(const type of ["gross_sale","refund","chargeback","processor_fee"])assert.ok(adapter.includes(type));
 assert.match(adapter,/if\(!factType\)\{ignored\+\+;continue;\}/);
});
test("provider sync endpoint is cron-authenticated and requires an authorized service identity",()=>{
 assert.match(route,/CRON_SECRET/);
 assert.match(route,/MME_FINANCIAL_WORKER_PERSON_ID/);
 assert.match(route,/mme_pos_authorize_financial_worker/);
 assert.match(route,/STRIPE_CREDENTIAL_NOT_CONFIGURED/);
});
test("provider pages are staged idempotently before durable cursor advancement",()=>{
 assert.match(route,/mme_pos_stage_financial_import_batch/);
 assert.match(route,/stripe-page-/);
 assert.match(route,/mme_pos_finish_financial_sync_run/);
 assert.match(route,/hasMore\?"partial":"completed"/);
});
test("dashboard API and workspace expose provider sync run history",()=>{
 assert.match(api,/mme_pos_financial_sync_runs/);
 assert.match(api,/sync_runs:syncRuns/);
 assert.match(page,/Synchronization history/);
});
test("Vercel Cron schedules provider sync independently of the import worker",()=>{
 assert.ok(config.crons.some(x=>x.path==="/api/cron/pos-financial-provider-sync"&&x.schedule==="*/5 * * * *"));
});

test("Stripe normalization preserves signed minor-unit amounts and emits fee facts",()=>{
 const result=normalizeStripeBalanceTransactions({timezone:"America/New_York",data:[
  {id:"txn_charge",type:"charge",reporting_category:"charge",amount:1200,fee:65,currency:"usd",created:1793900000,source:"ch_123"},
  {id:"txn_refund",type:"refund",reporting_category:"refund",amount:-400,fee:0,currency:"usd",created:1793900100,source:"re_123"},
  {id:"txn_dispute",type:"adjustment",reporting_category:"dispute",amount:-1200,fee:0,currency:"usd",created:1793900200,source:"dp_123"},
  {id:"txn_payout",type:"payout",reporting_category:"payout",amount:-500,fee:0,currency:"usd",created:1793900300,source:"po_123"}
 ]});
 assert.equal(result.records.length,4);
 assert.equal(result.ignored,1);
 assert.deepEqual(result.records.map(x=>x.fact_type),["gross_sale","processor_fee","refund","chargeback"]);
 assert.equal(result.records[0].amount_minor,1200);
 assert.equal(result.records[1].amount_minor,-65);
 assert.equal(result.records[2].amount_minor,-400);
 assert.equal(result.records[3].amount_minor,-1200);
 assert.match(result.records[0].source_digest_sha256,/^[a-f0-9]{64}$/);
 assert.equal(result.records[0].business_timezone,"America/New_York");
});
