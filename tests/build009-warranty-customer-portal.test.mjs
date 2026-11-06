import test from 'node:test'; import assert from 'node:assert/strict'; import {readFile} from 'node:fs/promises';
const sql=await readFile(new URL('../supabase/migrations/20261105001500_build009_warranty_customer_portal.sql',import.meta.url),'utf8');
test('portal has identity, preferences, claim views and requests',()=>{for(const n of ['mme_warranty_portal_access','mme_warranty_portal_preferences','mme_warranty_portal_claim_views','mme_warranty_portal_requests'])assert.ok(sql.includes('create table public.'+n));});
test('documents have size, checksum and malware scan states',()=>{assert.match(sql,/byte_size bigint not null check/);assert.match(sql,/checksum_sha256 text not null/);assert.match(sql,/scan_status text not null/);});
test('all portal tables have RLS and browser grants revoked',()=>{assert.match(sql,/alter table public.%I enable row level security/);assert.match(sql,/revoke all on public.%I from public,anon,authenticated/);});
test('requests are customer scoped and idempotent',()=>{assert.match(sql,/customer_identity_id uuid not null/);assert.match(sql,/idempotency_key text not null unique/);});
test('portal status avoids exposing provider internal state directly',()=>{assert.match(sql,/status_label text not null/);});
