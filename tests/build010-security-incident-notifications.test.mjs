import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const root=new URL("../",import.meta.url);
const read=p=>readFile(new URL(p,root),"utf8");
const sql=await read("supabase/migrations/20261106002190_build010_security_incident_notifications.sql");
const delivery=await read("supabase/migrations/20261105001290_build009_notification_delivery_infrastructure.sql");
const incident=await read("supabase/migrations/20261106002170_build010_security_incident_response_automation.sql");
const page=await read("app/warranty/security-intelligence/notifications/page.tsx");
const routingPage=await read("app/warranty/security-intelligence/notification-routing/page.tsx");
const routingApi=await read("app/api/warranty/security-intelligence/notification-routing/route.ts");
const route=await read("app/api/warranty/security-intelligence/notifications/route.ts");
test("security subscriptions and notification queue are RLS protected and service-role gated",()=>{
 assert.match(sql,/mme_security_incident_notification_subscriptions/);
 assert.match(sql,/mme_security_incident_notification_queue/);
 assert.match(sql,/enable row level security/g);
 assert.match(sql,/from public,anon,authenticated/);
});
test("incident events fan out by severity and role with idempotent recipient-channel keys",()=>{
 assert.match(sql,/after insert on public\.mme_security_incident_response_events/);
 assert.match(sql,/when 'critical' then s\.audience_role in \('ceo','cio','it_admin'\)/);
 assert.match(sql,/when 'warning' then s\.audience_role in \('cio','it_admin','manager'\)/);
 assert.match(sql,/on conflict\(event_id,recipient_person_id,channel\) do nothing/);
});
test("notifications reuse the shared provider-neutral Build 009 outbox",()=>{
 assert.match(sql,/mme_notification_enqueue_delivery/);
 assert.match(sql,/mme_notification_channel_preferences/);
 assert.match(delivery,/secret_reference/);
 assert.match(delivery,/for update skip locked/);
});
test("dispatch respects disabled recipient channels and retains blocked-template failures",()=>{
 assert.match(sql,/recipient_channel_disabled/);
 assert.match(sql,/status='blocked_template'/);
 assert.match(sql,/security-incident:/);
});
test("incident workflow remains auditable even if delivery is unavailable",()=>{
 assert.match(incident,/mme_security_incident_response_events/);
 assert.match(sql,/references public\.mme_security_incident_response_events/);
 assert.match(sql,/exception when others then/);
});
test("existing security notification center reports provider setup limits and supports acknowledgements",()=>{
 assert.match(page,/Security Notification Command Center/);
 assert.match(page,/Acknowledge notification/);
 assert.match(page,/External provider delivery is not configured/);
 assert.match(route,/record_delivery_result/);
 assert.match(route,/MME_NOTIFICATION_ADAPTER_SECRET/);
 assert.match(routingPage,/Security Notification Routing/);
 assert.match(routingPage,/Save subscription/);
 assert.match(routingApi,/auth\\/v1\\/user/);
 assert.match(routingApi,/subscription_admin_required/);
});
