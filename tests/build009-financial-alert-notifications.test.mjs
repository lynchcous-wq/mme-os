import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration=await readFile(new URL("../supabase/migrations/20261105001280_build009_financial_alert_notifications.sql",import.meta.url),"utf8");
const exceptions=await readFile(new URL("../supabase/migrations/20261105001250_build009_stripe_settlement_exception_intelligence.sql",import.meta.url),"utf8");
const intelligence=await readFile(new URL("../supabase/migrations/20261105001260_build009_stripe_financial_intelligence.sql",import.meta.url),"utf8");

test("alert, subscription, notification and event stores are RLS protected",()=>{
 assert.equal((migration.match(/enable row level security/g)||[]).length,4);
 assert.match(migration,/from public,anon,authenticated/);
 assert.match(migration,/revoke update,delete,truncate/);
});
test("subscriptions validate recipient and executive routing permission",()=>{
 assert.match(migration,/Active notification recipient required/);
 assert.match(migration,/p_audience_role='executive'/);
 assert.match(migration,/pos\.settlement\.approve/);
 assert.match(migration,/unique\(location_id,recipient_person_id,audience_role,channel\)/);
});
test("alert generation is idempotent and sourced from exception cases and risk snapshots",()=>{
 assert.match(migration,/dedupe_key text not null unique/);
 assert.match(migration,/on conflict\(dedupe_key\) do nothing/);
 assert.match(migration,/mme_pos_stripe_settlement_exception_cases/);
 assert.match(migration,/mme_pos_stripe_financial_intelligence_runs/);
 assert.match(exceptions,/due_at/);
 assert.match(intelligence,/risk_band/);
});
test("recipient routing is active-user scoped and supports executive and finance audiences",()=>{
 assert.match(migration,/mme_pos_financial_alert_subscriptions/);
 assert.match(migration,/lifecycle_status='active'/);
 assert.match(migration,/audience_role in \('executive','finance'\)/);
});
test("acknowledgment is authorized, recorded and rejects closed alerts",()=>{
 assert.match(migration,/mme_pos_acknowledge_financial_alert/);
 assert.match(migration,/Financial alert acknowledgment permission denied/);
 assert.match(migration,/Closed financial alert cannot be acknowledged/);
 assert.match(migration,/alert_acknowledged/);
});
test("SLA escalation and bounded concurrent outbox queue are supported",()=>{
 assert.match(migration,/mme_pos_escalate_financial_alerts/);
 assert.match(migration,/for update skip locked/);
 assert.match(migration,/p_batch_size>500/);
 assert.match(migration,/delivery_status='queued'/);
});
test("email is an outbox channel and is not falsely marked as delivered",()=>{
 assert.match(migration,/channel in \('in_app','email'\)/);
 assert.match(migration,/delivery_status in \('pending','queued','sent','failed','acknowledged'\)/);
 assert.match(migration,/separately deployed delivery worker/);
 assert.doesNotMatch(migration,/sendgrid|resend\.emails\.send|nodemailer\.send/i);
});
test("dashboard and recipient inbox views are provided without public access",()=>{
 assert.match(migration,/mme_pos_financial_alert_dashboard/);
 assert.match(migration,/mme_pos_financial_alert_inbox/);
 assert.match(migration,/security_invoker=true/);
});
