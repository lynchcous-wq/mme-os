import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const migration=await readFile(new URL("../supabase/migrations/20261105001150_build009_pos_financial_import_worker.sql",import.meta.url),"utf8");
const cron=await readFile(new URL("../app/api/cron/pos-financial-import/route.ts",import.meta.url),"utf8");
const webhook=await readFile(new URL("../app/api/webhooks/stripe/financial/route.ts",import.meta.url),"utf8");
const prior=await readFile(new URL("../supabase/migrations/20261105001140_build009_pos_financial_source_connectors.sql",import.meta.url),"utf8");
const config=await readFile(new URL("../vercel.json",import.meta.url),"utf8");

test("worker migration adds leased import queue, append-only worker events and webhook metadata",()=>{
 for(const t of ["mme_pos_financial_import_jobs","mme_pos_financial_worker_events","mme_pos_financial_webhook_events"])assert.ok(migration.includes(t));
});
test("worker tables use RLS and deny direct client access",()=>{
 assert.equal((migration.match(/enable row level security/g)||[]).length,3);
 assert.match(migration,/from public,anon,authenticated/);
});
test("worker identity must be active, employed and globally permissioned",()=>{
 assert.match(migration,/mme_pos_authorize_financial_worker/);
 assert.match(migration,/employee_access_frozen/);
 assert.match(migration,/scope='\{\}'::jsonb/);
});
test("job claims use row locks, leases and skip-locked concurrency",()=>{
 assert.match(migration,/for update skip locked/);
 assert.match(migration,/lease_token/);
 assert.match(migration,/lease_expires_at/);
});
test("worker retries use bounded attempts, exponential backoff and dead-letter handling",()=>{
 assert.match(migration,/max_attempts integer not null default 8/);
 assert.match(migration,/power\(2,/);
 assert.match(migration,/dead_letter/);
 assert.match(migration,/mme_pos_expire_financial_import_jobs/);
});
test("worker cannot complete a job until its batch reaches a terminal state",()=>{
 assert.match(migration,/Cannot complete job before its batch reaches a terminal state/);
 assert.match(migration,/completed_with_quarantine/);
});
test("verified webhook ledger stores event metadata and payload digest, not raw body",()=>{
 assert.match(migration,/payload_sha256/);
 assert.doesNotMatch(migration,/raw_payload|payload_body/);
 assert.match(migration,/unique\(connector_id,provider_event_id\)/);
});
test("cron route requires secret and dedicated employee service identity",()=>{
 assert.match(cron,/CRON_SECRET/);
 assert.match(cron,/MME_FINANCIAL_WORKER_PERSON_ID/);
 assert.match(cron,/mme_pos_authorize_financial_worker/);
 assert.match(cron,/mme_pos_claim_financial_import_job/);
 assert.match(cron,/mme_pos_finish_financial_import_job/);
});
test("Stripe webhook verifies signed timestamped payload with HMAC and constant-time comparison",()=>{
 assert.match(webhook,/stripe-signature/);
 assert.match(webhook,/createHmac\("sha256"/);
 assert.match(webhook,/timingSafeEqual/);
 assert.match(webhook,/300/);
});
test("Stripe webhook requires a unique active connected-account connector and persists only digest",()=>{
 assert.match(webhook,/external_account_reference/);
 assert.match(webhook,/provider_key:"eq\.stripe"/);
 assert.match(webhook,/createHash\("sha256"\)/);
 assert.match(webhook,/mme_pos_record_financial_webhook_event/);
 assert.doesNotMatch(webhook,/insert.*raw|payload_body/i);
});
test("scheduled worker is configured at five-minute cadence",()=>{
 assert.match(config,/"path": "\/api\/cron\/pos-financial-import"/);
 assert.match(config,/"schedule": "\*\/5 \* \* \* \*"/);
});
test("prior connector migration includes corrected SQL delimiters and row fingerprint check",()=>{
 assert.ok(prior.includes("row_fingerprint_md5 text not null check(row_fingerprint_md5 ~ '^[a-f0-9]{32}$')"));
 assert.match(prior,/as \$\$\s*declare v_connector public\.mme_pos_financial_connectors/);
 assert.match(prior,/end;\s*\$\$;/);
});

test("financial connector API exposes per-store worker and webhook monitoring",()=>{
 const apiSource=readFile(new URL("../app/api/pos/financial-connectors/route.ts",import.meta.url),"utf8");
 return apiSource.then(api=>{
  assert.match(api,/mme_pos_financial_import_jobs/);
  assert.match(api,/mme_pos_financial_webhook_events/);
 });
});
test("worker route supports Vercel cron GET requests",()=>{
 assert.match(cron,/export async function GET\(request:Request\)/);
});
