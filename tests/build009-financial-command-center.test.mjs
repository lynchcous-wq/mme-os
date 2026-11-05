import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration=await readFile(new URL("../supabase/migrations/20261105001270_build009_financial_command_center.sql",import.meta.url),"utf8");
const intelligence=await readFile(new URL("../supabase/migrations/20261105001260_build009_stripe_financial_intelligence.sql",import.meta.url),"utf8");
const exceptions=await readFile(new URL("../supabase/migrations/20261105001250_build009_stripe_settlement_exception_intelligence.sql",import.meta.url),"utf8");

test("executive briefing and store comparison records are RLS protected and append-only",()=>{
 assert.match(migration,/enable row level security/g);
 assert.match(migration,/from public,anon,authenticated/);
 assert.match(migration,/revoke update,delete,truncate/);
});
test("multi-store briefing requires bounded unique location scope and authorization for every store",()=>{
 assert.match(migration,/cardinality\(p_location_ids\)>100/);
 assert.match(migration,/Duplicate location identifiers are not allowed/);
 assert.match(migration,/pos\.settlement\.exception\.manage/);
 assert.match(migration,/Financial command center access denied/);
});
test("comparison is currency isolated and sourced from versioned intelligence snapshots",()=>{
 assert.match(migration,/distinct r\.currency/);
 assert.match(migration,/intelligence_run_id/);
 assert.match(migration,/source_run_ids/);
 assert.match(migration,/mme_pos_stripe_financial_intelligence_runs/);
 assert.match(intelligence,/risk_score/);
});
test("executive risk presentation preserves exception and settlement source domains",()=>{
 assert.match(migration,/mme_pos_stripe_settlement_exception_cases/);
 assert.match(migration,/mme_pos_settlement_batches/);
 assert.match(exceptions,/due_at/);
 assert.match(migration,/overdue_exception_count/);
 assert.match(migration,/delayed_settlement_count/);
});
test("dashboard is advisory and does not authorize money movement",()=>{
 assert.match(migration,/does not confirm bank deposits or authorize money movement/);
 assert.doesNotMatch(migration,/stripe\.refunds\.create|initiate_payout|ach_debit|wire_transfer/i);
});
test("comparison view is store-granular and currency-scoped",()=>{
 assert.match(migration,/mme_pos_financial_command_center_store_comparison/);
 assert.match(migration,/security_invoker=true/);
 assert.match(migration,/group by|distinct r\.currency/);
});
