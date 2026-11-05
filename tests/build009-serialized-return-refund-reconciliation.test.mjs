import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const migration=await readFile(new URL("../supabase/migrations/20261105001210_build009_serialized_return_refund_reconciliation.sql",import.meta.url),"utf8");
const returns=await readFile(new URL("../supabase/migrations/20261105001200_build009_serialized_returns_warranty_lifecycle.sql",import.meta.url),"utf8");
const refund=await readFile(new URL("../supabase/migrations/20261105000940_build009_pos_refund_void_controls.sql",import.meta.url),"utf8");
const settlement=await readFile(new URL("../supabase/migrations/20261105000950_build009_pos_refund_dispute_reconciliation.sql",import.meta.url),"utf8");
test("return refund link is one-to-one and RLS protected",()=>{
 assert.match(migration,/return_request_id uuid not null unique/);
 assert.match(migration,/refund_request_id uuid not null unique/);
 assert.match(migration,/alter table public\.mme_serialized_return_refund_links enable row level security/);
 assert.match(migration,/from public,anon,authenticated/);
});
test("refund preparation requires completed inspection and exact serialized line amount",()=>{
 assert.match(migration,/v_return\.status<>'inspection_resolved'/);
 assert.match(migration,/v_line\.quantity<>1 or p_amount_minor<>v_line\.line_total_cents/);
 assert.match(migration,/partial or adjusted refunds require manual review/);
 assert.match(migration,/mme_pos_request_refund_or_void/);
});
test("ambiguous and split tenders are sent to manual review",()=>{
 assert.match(migration,/eligible_tender_count/);
 assert.match(migration,/if v_count<>1 then/);
 assert.match(migration,/refund_exceeds_single_tender_balance/);
});
test("existing second-person approval and durable dispatch are reused",()=>{
 assert.match(refund,/mme_pos_decide_refund_request/);
 assert.match(refund,/requested_by_person_id = p_approver_person_id/);
 assert.match(refund,/mme_pos_claim_refund_dispatch/);
 assert.match(refund,/unknown_reconciliation/);
});
test("return is marked refunded only after completed provider outcome with matching references and amount",()=>{
 const trigger=migration.slice(migration.indexOf("create or replace function public.mme_pos_sync_serialized_return_refund_outcome"),migration.indexOf("create trigger mme_pos_sync_serialized_return_refund_outcome"));
 assert.match(trigger,/new\.status='completed'/);
 assert.match(trigger,/new\.provider_operation_reference is null/);
 assert.match(trigger,/new\.provider_refund_reference is null/);
 assert.match(trigger,/new\.amount_minor<>v_link\.amount_minor/);
 assert.match(trigger,/status='refunded'/);
 assert.match(trigger,/refund_status='confirmed'/);
});
test("failed and uncertain outcomes do not mark the return refunded",()=>{
 assert.match(migration,/new\.status='failed'/);
 assert.match(migration,/new\.status='unknown_reconciliation'/);
 assert.match(migration,/refund_status='manual_review'/);
});
test("settlement matching remains distinct from provider refund confirmation",()=>{
 assert.match(migration,/settlement_status=new\.provider_reconciliation_status/);
 assert.match(migration,/settlement_matched/);
 assert.match(migration,/settlement_mismatch/);
 assert.match(settlement,/mme_pos_reconcile_refund_settlement/);
});
test("refund workflow does not call payment provider from SQL",()=>{
 assert.doesNotMatch(migration,/stripe\.refunds\.create|fetch\(|https?\.request/);
});
test("return lifecycle refund statuses remain compatible",()=>{
 assert.match(returns,/refund_status text not null default 'not_started'/);
 assert.match(returns,/refund_status in \('not_started','pending_provider','confirmed','failed','manual_review'\)/);
});
