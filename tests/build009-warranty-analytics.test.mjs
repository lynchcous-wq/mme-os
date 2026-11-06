import test from 'node:test'; import assert from 'node:assert/strict'; import {readFile} from 'node:fs/promises';
const sql=await readFile(new URL('../supabase/migrations/20261105001510_build009_warranty_analytics.sql',import.meta.url),'utf8');
test('analytics facts distinguish actuals and projections',()=>{assert.match(sql,/realization text not null check\(realization in \('actual','projection'\)\)/);assert.match(sql,/realization<>'projection' or model_version is not null/);});
test('snapshots retain provenance and cannot combine currencies',()=>{assert.match(sql,/source_fact_count integer not null/);assert.match(sql,/currency_code text not null/);});
test('analytics assumptions are versioned and approved',()=>{assert.match(sql,/model_version text not null/);assert.match(sql,/approved_by uuid not null/);});
test('provider scorecards include SLA and reimbursement measures',()=>{assert.match(sql,/response_sla_pct/);assert.match(sql,/reimbursement_match_pct/);assert.match(sql,/late_response_count/);});
test('financial analytics group actual and projected entries separately',()=>{assert.match(sql,/group by entry_type,realization,currency_code/);});
test('lifecycle and provider SLA views are defined',()=>{assert.match(sql,/mme_warranty_lifecycle_analytics_v/);assert.match(sql,/mme_warranty_provider_sla_analytics_v/);});
test('all analytics tables use RLS and browser grants are revoked',()=>{assert.equal((sql.match(/enable row level security/g)||[]).length,4);assert.match(sql,/from public,anon,authenticated/);});
