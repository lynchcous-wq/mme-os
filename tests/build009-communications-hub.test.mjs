import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const migration=await readFile(new URL("../supabase/migrations/20261105001300_build009_customer_employee_communications_hub.sql",import.meta.url),"utf8");
const delivery=await readFile(new URL("../supabase/migrations/20261105001290_build009_notification_delivery_infrastructure.sql",import.meta.url),"utf8");
test("customer and employee communications have campaign, recipient and interaction records",()=>{
 for(const t of ["mme_communications_campaigns","mme_communications_campaign_recipients","mme_communications_interaction_history"]) assert.match(migration,new RegExp(t));
});
test("marketing sends require affirmative channel-specific consent and respect later opt-out",()=>{
 assert.match(migration,/consent_status='opted_in'/);
 assert.match(migration,/consent_status='opted_out'/);
 assert.match(migration,/suppressed_no_consent/);
 assert.match(migration,/purpose='marketing'/);
});
test("campaigns require separate approval and creator cannot approve own campaign",()=>{
 assert.match(migration,/pending_approval/);
 assert.match(migration,/created_by_person_id=p_actor_person_id/);
 assert.match(migration,/Campaign creator cannot approve their own campaign/);
});
test("campaign dispatch requires approval and dispatch permission",()=>{
 assert.match(migration,/status not in \('approved','dispatching'\)/);
 assert.match(migration,/communications\.dispatch/);
});
test("delivery is connected to Build 009.49 outbox with stable campaign idempotency",()=>{
 assert.match(migration,/mme_notification_enqueue_delivery/);
 assert.match(migration,/mme_pos_financial_notifications/);
 assert.doesNotMatch(migration,/mme_pos_financial_alert_notifications/);
 assert.match(migration,/campaign:'\|\|p_campaign_id::text/);
 assert.match(delivery,/idempotency_key text not null unique/);
});
test("consent, campaign and interaction data are protected by RLS and service-role grants",()=>{
 assert.match(migration,/enable row level security/g);
 assert.match(migration,/from public,anon,authenticated/);
 assert.match(migration,/grant execute on function public\.mme_communications_dispatch_recipient/);
});
test("customer communications retain source references and channel metadata",()=>{
 assert.match(migration,/source_reference/);
 assert.match(migration,/channel text not null/);
});
test("campaign analytics cover suppression, delivery and engagement",()=>{
 for(const metric of ["suppressed_no_consent","queued","sent","delivered","opened","clicked","unsubscribed"]) assert.ok(migration.includes(metric));
 assert.match(migration,/mme_communications_campaign_analytics/);
});
test("communication interaction history is append-only",()=>{
 assert.match(migration,/revoke update,delete,truncate on public\.mme_communications_interaction_history/);
});
test("campaign payloads and templates remain separated from provider credentials",()=>{
 assert.match(migration,/payload jsonb/);
 assert.match(delivery,/secret_reference/);
 assert.doesNotMatch(migration,/api_key|access_token|phone_number|email_address/i);
});
