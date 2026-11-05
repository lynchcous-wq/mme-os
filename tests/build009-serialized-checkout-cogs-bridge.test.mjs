import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const bridge=await readFile(new URL("../supabase/migrations/20261105001190_build009_serialized_checkout_cogs_bridge.sql",import.meta.url),"utf8");
const checkout=await readFile(new URL("../supabase/migrations/20261103000900_build001_serialized_checkout.sql",import.meta.url),"utf8");
const costing=await readFile(new URL("../supabase/migrations/20261105001180_build009_native_inventory_cogs_adapter.sql",import.meta.url),"utf8");
test("checkout-ready receiving links legacy serialized identities to actual-cost units",()=>{
 assert.match(bridge,/mme_pos_receive_serialized_inventory_checkout_ready/);
 assert.match(bridge,/mme_receive_serialized_unit/);
 assert.match(bridge,/serial_digest=v_serial_digest/);
 assert.match(bridge,/legacy_serialized_unit_id=v_legacy_unit_id/);
 assert.match(bridge,/actor_person_id<>approved_by_identity_id|p_actor_person_id=p_approved_by_person_id/);
});
test("serialized order line reservation also reserves exactly one matching cost unit",()=>{
 assert.match(bridge,/after insert on public\.mme_order_lines/);
 assert.match(bridge,/new\.quantity<>1/);
 assert.match(bridge,/legacy_serialized_unit_id=new\.serialized_unit_id/);
 assert.match(bridge,/reserved_quantity=reserved_quantity\+1/);
 assert.match(bridge,/inventory_serial_unit_id=v_unit\.id/);
});
test("legacy release and expiry release the linked cost reservation",()=>{
 assert.match(checkout,/mme_release_serialized_order_reservation/);
 assert.match(bridge,/after update of status on public\.mme_serialized_unit_reservations/);
 assert.match(bridge,/new\.status not in \('released','expired'\)/);
 assert.match(bridge,/status='available',reserved_order_id=null/);
 assert.match(bridge,/reserved_quantity=reserved_quantity-1/);
});
test("verified Stripe success captures serialized COGS only after consumed reservation",()=>{
 assert.match(checkout,/payment_intent\.succeeded/);
 assert.match(bridge,/before update of status on public\.mme_orders/);
 assert.match(bridge,/new\.status<>'paid'/);
 assert.match(bridge,/status='consumed'/);
 assert.match(bridge,/v_unit\.status<>'reserved'/);
 assert.match(bridge,/status='sold',reserved_order_id=null/);
 assert.match(bridge,/mme_order_inventory_cogs_snapshots/);
 assert.match(bridge,/unit_cost_cents/);
});
test("paid order COGS export is store-timezone aware and idempotent by order line",()=>{
 assert.match(bridge,/mme_pos_export_serialized_order_cogs/);
 assert.match(bridge,/business_timezone/);
 assert.match(bridge,/web-order:/);
 assert.match(bridge,/cost_of_goods_sold/);
 assert.match(bridge,/mme_pos_import_financial_fact/);
});
test("new COGS snapshot table is protected from browser roles",()=>{
 assert.match(bridge,/alter table public\.mme_order_inventory_cogs_snapshots enable row level security/);
 assert.match(bridge,/revoke all on public\.mme_order_inventory_cogs_snapshots from public,anon,authenticated/);
 assert.match(bridge,/grant all on public\.mme_order_inventory_cogs_snapshots to service_role/);
});
test("serialized sale bridge does not weaken the existing checkout idempotency and payment validation",()=>{
 assert.match(checkout,/Idempotency key reused with different request/);
 assert.match(checkout,/p_amount_received_cents/);
 assert.match(checkout,/amount_or_currency_mismatch/);
 assert.match(costing,/mme_inventory_serial_cost_units/);
});
