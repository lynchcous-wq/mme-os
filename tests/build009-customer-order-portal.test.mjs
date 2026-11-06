import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const sql=await readFile(new URL("../supabase/migrations/20261105001320_build009_customer_order_self_service_portal.sql",import.meta.url),"utf8");
test("customer portal has account links and order, fulfillment, refund, warranty and subscription projections",()=>{
 for(const name of ["mme_customer_account_links","mme_customer_order_portal","mme_customer_order_fulfillment_portal","mme_customer_order_refund_portal","mme_customer_order_warranty_portal","mme_customer_subscription_portal"]) assert.ok(sql.includes(name));
});
test("all customer data surfaces enable RLS and authenticated read grants",()=>{
 assert.equal((sql.match(/enable row level security/g)||[]).length,7);
 assert.match(sql,/grant select on public\.mme_customer_order_portal/);
 assert.match(sql,/auth\.uid\(\)/);
 assert.match(sql,/link_status='active'/);
});
test("order and related data are scoped to the linked authenticated customer",()=>{
 for(const name of ["mme_customer_order_self_read","mme_customer_fulfillment_self_read","mme_customer_refund_self_read","mme_customer_warranty_self_read","mme_customer_subscription_self_read"]) assert.ok(sql.includes(name));
});
test("service requests derive person identity from auth uid and validate ownership",()=>{
 assert.match(sql,/mme_customer_portal_submit_service_request/);
 assert.match(sql,/where l\.auth_user_id=auth\.uid\(\) and l\.link_status='active'/);
 assert.match(sql,/o\.order_id=p_order_id and o\.person_id=v_person_id/);
 assert.match(sql,/one_open_request_idx/);
});
test("cancellation and return requests have distinct eligibility guards",()=>{
 assert.match(sql,/no longer eligible for cancellation/);
 assert.match(sql,/Return requests require an eligible fulfilled order/);
});
test("account linking and order projections are trusted service-role operations",()=>{
 assert.match(sql,/mme_customer_portal_provision_account_link/);
 assert.match(sql,/mme_customer_portal_upsert_order_snapshot/);
 assert.match(sql,/mme_customer_portal_upsert_fulfillment_snapshot/);
 assert.match(sql,/to service_role/);
 assert.match(sql,/from public,anon,authenticated/);
});
test("tracking URLs are HTTPS and financial amounts are nonnegative",()=>{
 assert.match(sql,/tracking_url is null or tracking_url ~ '\^https:\/\//);
 assert.match(sql,/order_total>=0/);
 assert.match(sql,/refund_amount>=0/);
});
test("customer projections avoid payment credentials and raw payment card data",()=>{
 assert.doesNotMatch(sql,/card_number|cvv|cvc|access_token|secret_key|payment_method_token/i);
});
test("customer request notes are length bounded and status transitions are controlled",()=>{
 assert.match(sql,/length\(p_customer_note\)>1000/);
 assert.match(sql,/request_status text not null default 'submitted'/);
});
