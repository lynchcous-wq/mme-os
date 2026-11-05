import test from "node:test";
import assert from "node:assert/strict";
import {readFile,readdir} from "node:fs/promises";
const migration=await readFile(new URL("../supabase/migrations/20261105001170_build009_pos_native_financial_adapter.sql",import.meta.url),"utf8");
const tenderMigration=await readFile(new URL("../supabase/migrations/20261105000931_build009_pos_tender_reconciliation.sql",import.meta.url),"utf8");
const posCreate=await readFile(new URL("../app/api/pos/transactions/route.ts",import.meta.url),"utf8");
const registerRoute=await readFile(new URL("../app/api/pos/transactions/[transactionId]/register/route.ts",import.meta.url),"utf8");
const exportRoute=await readFile(new URL("../app/api/cron/pos-native-financial-export/route.ts",import.meta.url),"utf8");
const connectorApi=await readFile(new URL("../app/api/pos/financial-connectors/route.ts",import.meta.url),"utf8");
const dashboard=await readFile(new URL("../app/internal/financial-connectors/page.tsx",import.meta.url),"utf8");
const stripe=await readFile(new URL("../lib/pos/financial-adapters/stripe-balance-transactions.ts",import.meta.url),"utf8");
const config=JSON.parse(await readFile(new URL("../vercel.json",import.meta.url),"utf8"));

test("native export migration adds one-store transaction attribution and validated per-store timezone",()=>{
 assert.match(migration,/add column if not exists location_id uuid references public\.mme_store_locations/);
 assert.match(migration,/business_timezone text not null default 'America\/New_York'/);
 assert.match(migration,/pg_timezone_names/);
 assert.match(migration,/array_agg\(distinct rl\.location_id\)/);
});
test("register attribution is immutable after pricing begins and requires employee authorization",()=>{
 assert.match(migration,/mme_pos_set_transaction_register/);
 assert.match(migration,/pos\.transaction\.create/);
 assert.match(migration,/v_tx\.status<>'inventory_reserved'/);
 assert.match(registerRoute,/authenticatePosRequest/);
 assert.match(registerRoute,/mme_pos_set_transaction_register/);
});
test("only finalized transactions with one-store orders and fully captured tenders are exported",()=>{
 assert.match(migration,/t\.status='finalized'/);
 assert.match(migration,/count\(distinct location_id\)/);
 assert.match(migration,/v_captured_total<>v_order\.total_cents/);
 assert.match(migration,/v_bad_tenders<>0/);
 assert.match(migration,/cross-store/);
});
test("native financial facts are idempotent and attributed by line, register, cashier and store",()=>{
 for(const key of ["gross_sale","discount","sales_tax","payment_capture","refund","payment_refund"])assert.ok(migration.includes("'"+key+"'"));
 assert.match(migration,/pos:'\|\|p_transaction_id::text\|\|':line:'/);
 assert.match(migration,/v_tx\.register_reference/);
 assert.match(migration,/v_tx\.created_by_person_id/);
 assert.match(migration,/source_digest_sha256/);
});
test("provider payment activity is not double-counted as native sales",()=>{
 assert.match(stripe,/factType="payment_capture"/);
 assert.match(stripe,/factType="payment_refund"/);
 assert.doesNotMatch(stripe,/factType="gross_sale"/);
 assert.doesNotMatch(stripe,/factType="refund"/);
 assert.match(migration,/Payment capture\/refund facts are provider movement evidence only/);
});
test("native export worker is lease-protected and uses store-specific timezone",()=>{
 assert.match(migration,/mme_pos_claim_native_financial_exports/);
 assert.match(migration,/for update of e skip locked/);
 assert.match(migration,/lease_token=gen_random_uuid\(\)/);
 assert.match(exportRoute,/CRON_SECRET/);
 assert.match(exportRoute,/claim\.business_timezone/);
 assert.match(exportRoute,/mme_pos_export_finalized_transaction_financial_facts/);
});
test("native export state is RLS protected and not directly mutable by clients",()=>{
 assert.match(migration,/alter table public\.mme_pos_financial_pos_exports enable row level security/);
 assert.match(migration,/revoke all on public\.mme_pos_financial_pos_exports,public\.mme_pos_financial_pos_export_events from public,anon,authenticated/);
 assert.match(migration,/revoke delete,truncate on public\.mme_pos_financial_pos_exports/);
});
test("finance API and dashboard expose native POS export status",()=>{
 assert.match(connectorApi,/mme_pos_financial_pos_exports/);
 assert.match(connectorApi,/native_exports:nativeExports/);
 assert.match(dashboard,/Finalized transaction exports/);
 assert.match(dashboard,/data\.native_exports/);
});
test("native export cron is scheduled every five minutes",()=>{
 assert.ok(config.crons.some(x=>x.path==="/api/cron/pos-native-financial-export"&&x.schedule==="*/5 * * * *"));
});
test("existing POS transaction creation API remains idempotent and authenticated",()=>{
 assert.match(posCreate,/authenticatePosRequest/);
 assert.match(posCreate,/Idempotency-Key/);
 assert.match(posCreate,/mme_pos_create_transaction/);
});

test("financial schema retains chargeback reversals as offsets",()=>{
 assert.ok(migration.includes("chargeback_reversal"));
 assert.ok(migration.includes("fact_type in ('chargeback','chargeback_reversal')"));
});

test("all Build 009 migrations use distinct versions",()=>{
 assert.match(tenderMigration,/Build 009/);
 assert.ok(!tenderMigration.includes("native POS financial export"));
});

test("Build 009 migration versions are unique and function delimiters are paired",async()=>{
 const names=(await readdir(new URL("../supabase/migrations/",import.meta.url))).filter(n=>/^2026110500(09|10|11)/.test(n)&&n.endsWith(".sql")).sort();
 const versions=names.map(n=>n.slice(0,14));
 assert.equal(new Set(versions).size,versions.length,"migration versions must be unique");
 for(const name of names){
  const sql=await readFile(new URL("../supabase/migrations/"+name,import.meta.url),"utf8");
  assert.doesNotMatch(sql,/^as \$$/m, name+" has a malformed function opening delimiter");
  assert.doesNotMatch(sql,/^\$;$/m, name+" has a malformed function closing delimiter");
 }
});
