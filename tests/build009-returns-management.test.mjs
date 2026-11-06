import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const sql=await readFile(new URL("../supabase/migrations/20261105001330_build009_returns_exchanges_refunds.sql",import.meta.url),"utf8");
const portal=await readFile(new URL("../supabase/migrations/20261105001320_build009_customer_order_self_service_portal.sql",import.meta.url),"utf8");
test("returns workflow covers cases, item records, inspections, evidence, refunds, exchanges and audit",()=>{
 for(const t of ["mme_return_cases","mme_return_case_items","mme_return_inspections","mme_return_evidence","mme_return_refund_decisions","mme_return_exchanges","mme_return_audit_events"]) assert.ok(sql.includes(t));
});
test("all returns tables enable row-level security",()=>assert.equal((sql.match(/enable row level security/g)||[]).length,7));
test("customer case, item, refund and exchange reads require active account ownership",()=>{
 for(const p of ["mme_return_case_customer_read","mme_return_item_customer_read","mme_return_refund_customer_read","mme_return_exchange_customer_read"]) assert.ok(sql.includes(p));
 assert.match(sql,/auth\.uid\(\)/);
});
test("return cases originate from the customer's existing return request",()=>{
 assert.match(sql,/references public\.mme_customer_order_service_requests\(request_id\)/);
 assert.match(sql,/v_req\.request_type<>'return'/);
});
test("device inspection captures serial, activation lock, battery, screen, ports, camera and accessories",()=>{
 for(const field of ["serial_match","activation_lock_status","battery_health_percent","screen_status","ports_status","camera_status","accessory_completeness"]) assert.ok(sql.includes(field));
});
test("non-resellable, serial-mismatched and activation-locked devices cannot be restocked",()=>{
 assert.match(sql,/Non-resellable item cannot be restocked/);
 assert.match(sql,/Serial mismatch or activation lock prevents restocking/);
 assert.match(sql,/Item has not passed restock safety gates/);
});
test("refund requests require inspection and independent approval",()=>{
 assert.match(sql,/All returned items require completed inspection/);
 assert.match(sql,/Independent refund approver required/);
 assert.match(sql,/approved_by<>requested_by/);
});
test("refund processor outcomes require approval and are tracked independently",()=>{
 assert.match(sql,/Approved refund required/);
 assert.match(sql,/processor_reference/);
 assert.match(sql,/refund_completed/);
});
test("refund requests are idempotent and amount/currency validated",()=>{
 assert.match(sql,/idempotency_key text not null unique/);
 assert.match(sql,/p_amount<=0/);
 assert.match(sql,/currency_code ~ '\^[A-Z]\{3\}\$'/);
});
test("service functions are restricted to service role",()=>{
 assert.match(sql,/revoke all on function public\.mme_return_refund_decide/);
 assert.match(sql,/grant execute on function public\.mme_return_refund_decide.*to service_role/s);
});
test("audit events are append only and evidence uses storage object paths",()=>{
 assert.match(sql,/revoke update,delete,truncate on public\.mme_return_audit_events/);
 assert.match(sql,/storage_object_path text not null/);
});
test("portal return request remains a request and does not execute a refund",()=>{
 assert.match(portal,/Return requests require an eligible fulfilled order/);
 assert.doesNotMatch(portal,/stripe\.refunds\.create/);
});
