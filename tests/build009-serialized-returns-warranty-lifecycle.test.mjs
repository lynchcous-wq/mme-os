import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const migration=await readFile(new URL("../supabase/migrations/20261105001200_build009_serialized_returns_warranty_lifecycle.sql",import.meta.url),"utf8");
const submit=await readFile(new URL("../supabase/migrations/20261103008000_build001_atomic_inspection_submission.sql",import.meta.url),"utf8");
const disposition=await readFile(new URL("../supabase/migrations/20261103008200_build001_serialized_unit_disposition_ledger.sql",import.meta.url),"utf8");
test("inspection workflow synchronizes serialized cost states and event types",()=>{
 assert.match(migration,/mme_pos_sync_serialized_inspection_cost_ledger/);
 assert.match(migration,/status in \('available','reserved','sold','repair','quarantined','written_off','returned_to_supplier','returned'\)/);
 assert.match(migration,/event_type in \('received','reserved','released','sold','repair','quarantined','returned','written_off','returned_to_supplier'\)/);
 assert.match(migration,/after insert or update of disposition on public\.mme_inventory_inspections/);
});
test("inspection intake removes available unit from aggregate stock and records movement",()=>{
 assert.match(migration,/prior_cost_status/);
 assert.match(migration,/movement_type,quantity_delta/);
 assert.match(migration,/adjustment_decrease/);
 assert.match(migration,/v_after:=v_before-1/);
 assert.match(migration,/set on_hand_quantity=v_after/);
});
test("saleable disposition restores one costed unit and preserves sale-time COGS history",()=>{
 assert.match(disposition,/mme_serialized_unit_dispositions/);
 assert.match(migration,/return_to_stock/);
 assert.match(migration,/average_unit_cost_cents=case when v_before=0/);
 assert.match(migration,/adjustment_increase/);
 assert.match(migration,/Cost ledger match required before serialized unit can return to sellable stock/);
 assert.match(migration,/mme_inventory_serial_cost_events/);
});
test("customer returns require paid order ownership, configured store policy and return window",()=>{
 assert.match(migration,/mme_serialized_return_policies/);
 assert.match(migration,/enabled boolean not null default false/);
 assert.match(migration,/v_order\.customer_identity_id<>p_customer_identity_id/);
 assert.match(migration,/return_window_days/);
 assert.match(migration,/mme_serialized_return_one_open_per_line/);
 assert.match(migration,/Return idempotency key reused with different request/);
});
test("return intake and resolution require scoped employee permissions",()=>{
 assert.match(migration,/mme_employee_authorize_inventory_action\(p_actor_user_id,'inventory\.inspection\.submit'/);
 assert.match(migration,/mme_submit_serialized_inspection/);
 assert.match(migration,/p_actor_user_id=p_approver_user_id/);
 assert.match(migration,/inventory\.inspection\.resolve/);
 assert.match(migration,/inventory\.inspection\.approve/);
 assert.match(submit,/mme_employee_authorize_inventory_action/);
});
test("warranty registration stores supplied terms and exact coverage dates",()=>{
 assert.match(migration,/mme_serialized_warranties/);
 assert.match(migration,/terms_snapshot jsonb not null/);
 assert.match(migration,/p_expires_at<=v_order\.paid_at/);
 assert.match(migration,/provider_name/);
 assert.match(migration,/plan_name/);
});
test("warranty claims validate ownership, active coverage and idempotency",()=>{
 assert.match(migration,/mme_serialized_warranty_claims/);
 assert.match(migration,/v_warranty\.customer_identity_id<>p_customer_identity_id/);
 assert.match(migration,/now\(\)>v_warranty\.expires_at/);
 assert.match(migration,/Warranty claim idempotency key reused with different request/);
 assert.match(migration,/mme_pos_receive_serialized_warranty_claim/);
});
test("return and warranty records are protected from direct browser access",()=>{
 for(const table of ["mme_serialized_return_policies","mme_serialized_return_requests","mme_serialized_warranties","mme_serialized_warranty_claims"])
  assert.ok(migration.includes("alter table public."+table+" enable row level security"));
 assert.match(migration,/from public,anon,authenticated/);
 assert.match(migration,/to service_role/);
});
test("inspection resolution does not itself issue an unverified refund",()=>{
 assert.match(migration,/refund_status text not null default 'not_started'/);
 assert.match(migration,/Refunds remain pending until a separately verified provider refund outcome is recorded/);
 assert.doesNotMatch(migration,/stripe\.refunds\.create|payment_intent\.cancel/);
});
