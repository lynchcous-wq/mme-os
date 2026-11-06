import test from 'node:test'; import assert from 'node:assert/strict'; import {readFile} from 'node:fs/promises';
const sql=await readFile(new URL('../supabase/migrations/20261105001490_build009_warranty_lifecycle_automation.sql',import.meta.url),'utf8');
test('lifecycle schema covers core workflows',()=>{for(const n of ['mme_warranty_lifecycle_records','mme_warranty_lifecycle_events','mme_warranty_lifecycle_jobs','mme_warranty_customer_notifications','mme_warranty_renewal_offers','mme_warranty_transfer_requests','mme_warranty_cancellation_requests','mme_warranty_eligibility_checks','mme_warranty_replacement_reviews']) assert.ok(sql.includes('create table public.'+n));});
test('all nine tables have RLS and browser access revoked',()=>{assert.match(sql,/enable row level security/);assert.match(sql,/revoke all on public.%I from public,anon,authenticated/);});
test('durable jobs are retryable and idempotent',()=>{assert.match(sql,/status in \('queued','processing','succeeded','retry','failed','dead_letter','cancelled'\)/);assert.match(sql,/idempotency_key text not null unique/);});
test('customer messages include suppression state',()=>{assert.match(sql,/suppressed/);});
test('eligibility snapshots retain policy and rationale',()=>{assert.match(sql,/policy_version text not null/);assert.match(sql,/reason_code text not null/);});
test('replacement is a human-reviewed decision workflow',()=>{assert.match(sql,/status in \('pending','approved','rejected','completed'\)/);});
