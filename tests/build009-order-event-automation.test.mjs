import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const migration=await readFile(new URL("../supabase/migrations/20261105001310_build009_customer_order_event_automation.sql",import.meta.url),"utf8");
const comms=await readFile(new URL("../supabase/migrations/20261105001300_build009_customer_employee_communications_hub.sql",import.meta.url),"utf8");
const delivery=await readFile(new URL("../supabase/migrations/20261105001290_build009_notification_delivery_infrastructure.sql",import.meta.url),"utf8");
const alertSchema=await readFile(new URL("../supabase/migrations/20261105001280_build009_financial_alert_notifications.sql",import.meta.url),"utf8");
test("commerce events cover orders, payments, shipping, pickup, returns, refunds and lifecycle reminders",()=>{
 for(const e of ["order_placed","payment_succeeded","payment_failed","shipment_label_created","shipment_in_transit","shipment_delivered","pickup_ready","pickup_reminder_due","return_authorized","refund_initiated","refund_completed","refund_failed","warranty_expiry_reminder_due","subscription_renewal_reminder_due"]) assert.ok(migration.includes(e));
});
test("event ingestion is idempotent and requires an active customer identity",()=>{
 assert.match(migration,/unique\(source_system,source_event_id\)/);
 assert.match(migration,/on conflict\(source_system,source_event_id\)/);
 assert.match(migration,/lifecycle_status='active'/);
});
test("dispatch uses configured templates and the existing delivery outbox",()=>{
 assert.match(migration,/mme_customer_order_notification_rules/);
 assert.match(migration,/mme_notification_enqueue_delivery/);
 assert.match(delivery,/idempotency_key text not null unique/);
});
test("channel preferences and inactive identities suppress dispatch",()=>{
 assert.match(migration,/suppressed_preference/);
 assert.match(migration,/suppressed_inactive/);
 assert.match(migration,/not p\.enabled/);
});
test("stable event, recipient and channel idempotency prevents duplicate dispatch",()=>{
 assert.match(migration,/commerce-event:/);
 assert.match(migration,/unique\(event_id,person_id,channel\)/);
 assert.match(migration,/on conflict\(event_id,person_id,channel\) do nothing/);
});
test("event processing is bounded and records partial completion and failure",()=>{
 assert.match(migration,/p_batch_size not between 1 and 4/);
 assert.match(migration,/partially_dispatched/);
 assert.match(migration,/processing_status='failed'/);
});
test("dispatch data does not include raw contact data or provider credentials",()=>{
 assert.match(migration,/jsonb_build_object/);
 assert.doesNotMatch(migration,/email_address|phone_number|device_token|api_key|access_token/i);
 assert.match(delivery,/secret_reference/);
});
test("all new tables use RLS and service-role-only access",()=>{
 assert.match(migration,/enable row level security/g);
 assert.match(migration,/from public,anon,authenticated/);
 assert.match(migration,/grant execute on function public\.mme_customer_order_notification_ingest_event/);
});
test("operational health aggregates events and dispatches",()=>{
 assert.match(migration,/mme_customer_order_notification_health/);
 assert.match(migration,/queued_count/);
 assert.match(migration,/suppressed_count/);
});
test("communications and delivery dependencies are present",()=>{
 assert.match(comms,/mme_communications_interaction_history/);
 assert.match(delivery,/mme_notification_delivery_jobs/);
});

test("Build 009.49 financial notification foreign key and status fields match Build 009.48 schema",()=>{
 assert.match(delivery,/references public\\.mme_pos_financial_alert_notifications\\(id\\)/);
 assert.match(delivery,/set delivery_status='sent',sent_at=now\(\)/);
 assert.match(delivery,/delivery_attempts=least\(20,delivery_attempts\+1\)/);
 assert.match(alertSchema,/create table public\\.mme_pos_financial_alert_notifications/);
 assert.match(alertSchema,/sent_at timestamptz/);
 assert.match(alertSchema,/delivery_attempts integer/);
 assert.doesNotMatch(delivery,/mme_pos_financial_notifications\\(/);
});
test("Build 009.50 campaign RPC grant matches its location-scoped function signature",()=>{
 assert.match(comms,/grant execute on function public\\.mme_communications_create_campaign\\(text,text,text,text,text,text,text,text,uuid,uuid,timestamptz\\) to service_role/);
});
test("events without configured notification rules close as suppressed rather than retrying forever",()=>{
 assert.match(migration,/when not exists\\(select 1 from public\\.mme_customer_order_notification_rules r/);
 assert.match(migration,/then 'suppressed'/);
});
