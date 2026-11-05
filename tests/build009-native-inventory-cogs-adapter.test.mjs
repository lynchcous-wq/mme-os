import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const migration=await readFile(new URL("../supabase/migrations/20261105001180_build009_native_inventory_cogs_adapter.sql",import.meta.url),"utf8");
const exportMigration=await readFile(new URL("../supabase/migrations/20261105001170_build009_pos_native_financial_adapter.sql",import.meta.url),"utf8");
const reporting=await readFile(new URL("../supabase/migrations/20261105001130_build009_pos_financial_reporting.sql",import.meta.url),"utf8");
const serialRoute=await readFile(new URL("../app/api/pos/inventory/serialized/assign/route.ts",import.meta.url),"utf8");
const connectorRoute=await readFile(new URL("../app/api/pos/financial-connectors/route.ts",import.meta.url),"utf8");
const dashboard=await readFile(new URL("../app/internal/financial-connectors/page.tsx",import.meta.url),"utf8");
test("landed cost components require dual approval and use explicit allocation bases",()=>{
 assert.match(migration,/mme_inventory_receipt_cost_components/);
 assert.match(migration,/actor_identity_id<>approved_by_identity_id/);
 assert.match(migration,/pos\.inventory\.cost\.manage/);
 assert.match(migration,/pos\.inventory\.cost\.approve/);
 assert.match(migration,/extended_cost/);
 assert.match(migration,/quantity/);
 assert.match(migration,/mme_pos_allocate_receipt_landed_cost/);
});
test("landed costs are allocated by receipt lines with a deterministic remainder",()=>{
 assert.match(migration,/row_number\(\) over\(order by m\.id\)/);
 assert.match(migration,/v_remaining:=v_remaining-v_alloc/);
 assert.match(migration,/average_unit_cost_cents=average_unit_cost_cents\+v_delta/);
 assert.match(migration,/Landed cost must be recorded before subsequent inventory movements/);
});
test("serialized receipt records unit costs without storing raw serial or IMEI",()=>{
 assert.match(migration,/mme_inventory_serial_cost_units/);
 assert.match(migration,/serial_digest text/);
 assert.match(migration,/imei_digest text/);
 assert.match(migration,/encode\(digest\(lower\(btrim\(v_item\.serial_number\)\),'sha256'\),'hex'\)/);
 assert.match(migration,/regexp_replace\(v_item\.imei,'\[\^0-9\]','','g'\)/);
 assert.doesNotMatch(migration,/serial_number text not null,/);
});
test("serialized units require separate approval and a store-matched reservation",()=>{
 assert.match(migration,/mme_pos_receive_serialized_inventory/);
 assert.match(migration,/mme_pos_assign_serial_unit_to_order_line/);
 assert.match(migration,/v_unit\.status<>'available'/);
 assert.match(migration,/v_unit\.reserved_order_id/);
 assert.match(migration,/p_actor_person_id=p_approved_by_person_id/);
});
test("finalized POS status consumes reserved inventory atomically and snapshots cost",()=>{
 assert.match(migration,/mme_pos_apply_inventory_sale_and_snapshot_cogs/);
 assert.match(migration,/new\.status='finalized'/);
 assert.match(migration,/status='consumed'/);
 assert.match(migration,/cost_method in \('weighted_average','serialized_unit'\)/);
 assert.match(migration,/status='sold'/);
 assert.match(migration,/reserved_quantity=reserved_quantity-v_line\.quantity/);
});
test("COGS is exported as a negative inventory fact with idempotent transaction-line reference",()=>{
 assert.match(migration,/cost_of_goods_sold/);
 assert.match(migration,/:cogs:/);
 assert.match(migration,/v_line\.total_cost_cents/);
 assert.match(migration,/mme_pos_inventory_cogs_snapshots/);
 assert.match(reporting,/cost_of_goods_sold_minor/);
});
test("new inventory costing tables are RLS protected and client access is revoked",()=>{
 for(const table of ["mme_inventory_receipt_cost_components","mme_inventory_receipt_cost_allocations","mme_inventory_serial_cost_units","mme_inventory_serial_cost_events","mme_pos_inventory_cogs_snapshots"]){
  assert.ok(migration.includes("alter table public."+table+" enable row level security"));
  assert.ok(migration.includes("public."+table+" from public,anon,authenticated"));
 }
});
test("inventory sale trigger and privileged RPCs are not directly executable by clients",()=>{
 assert.match(migration,/revoke all on function public\.mme_pos_apply_inventory_sale_and_snapshot_cogs\(\) from public,anon,authenticated/);
 assert.match(migration,/revoke all on function public\.mme_pos_receive_serialized_inventory/);
 assert.match(migration,/grant execute on function public\.mme_pos_export_finalized_transaction_financial_facts/);
});

test("serialized inventory assignment API authenticates employee and accepts only identifiers",()=>{
 assert.match(serialRoute,/authenticatePosRequest/);
 assert.match(serialRoute,/isUuid\(b\.order_line_id\)/);
 assert.match(serialRoute,/isUuid\(b\.serial_unit_id\)/);
 assert.match(serialRoute,/mme_pos_assign_serial_unit_to_order_line/);
 assert.doesNotMatch(serialRoute,/serial_number|imei/);
});
test("finance connector workspace exposes store-scoped COGS snapshots",()=>{
 assert.match(connectorRoute,/mme_pos_inventory_cogs_snapshots/);
 assert.match(connectorRoute,/cogs_snapshots:cogsSnapshots/);
 assert.match(dashboard,/POS cost of goods sold snapshots/);
 assert.match(dashboard,/data\.cogs_snapshots/);
});
