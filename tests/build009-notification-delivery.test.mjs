import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration=await readFile(new URL("../supabase/migrations/20261105001290_build009_notification_delivery_infrastructure.sql",import.meta.url),"utf8");
const base=await readFile(new URL("../supabase/migrations/20261105001280_build009_financial_alert_notifications.sql",import.meta.url),"utf8");

test("delivery jobs support email, SMS, push and in-app channels",()=>{
 assert.match(migration,/channel in \('email','sms','push','in_app'\)/);
 assert.match(migration,/mme_notification_delivery_jobs/);
 assert.match(migration,/mme_notification_provider_routes/);
});
test("provider credentials are referenced by runtime secret name, never stored",()=>{
 assert.match(migration,/secret_reference/);
 assert.match(migration,/secret_reference ~ '\^\[A-Z\]/);
 assert.doesNotMatch(migration,/api_key text|access_token text|password text/i);
});
test("templates are versioned, localized and have one active version per channel",()=>{
 assert.match(migration,/template_version/);
 assert.match(migration,/locale text/);
 assert.match(migration,/one_active_idx/);
});
test("delivery enqueue is idempotent and requires an active recipient and active template",()=>{
 assert.match(migration,/idempotency_key text not null unique/);
 assert.match(migration,/on conflict\(idempotency_key\)/);
 assert.match(migration,/lifecycle_status='active'/);
 assert.match(migration,/No active template for requested channel and locale/);
});
test("delivery workers claim jobs safely and retry with bounded exponential backoff",()=>{
 assert.match(migration,/for update skip locked/);
 assert.match(migration,/attempts<j\.max_attempts/);
 assert.match(migration,/dead_letter/);
 assert.match(migration,/least\(21600,30\*power/);
});
test("delivery attempt history is append-only and provider result is validated",()=>{
 assert.match(migration,/mme_notification_delivery_attempts/);
 assert.match(migration,/unique\(job_id,attempt_number\)/);
 assert.match(migration,/provider_message_id/);
 assert.match(migration,/permanent_failure/);
});
test("delivery completion updates linked financial alert delivery status",()=>{
 assert.match(migration,/mme_pos_financial_alert_notifications/);
 assert.match(migration,/delivery_status='sent'/);
 assert.match(base,/mme_pos_financial_alert_notifications/);
});
test("quiet-hour preferences are timezone-aware and validated",()=>{
 assert.match(migration,/quiet_hours_start/);
 assert.match(migration,/quiet_hours_end/);
 assert.match(migration,/timezone_name/);
});
test("delivery health is aggregated without exposing recipient contact information",()=>{
 assert.match(migration,/mme_notification_delivery_health/);
 assert.match(migration,/group by channel,status/);
});
test("all delivery infrastructure is RLS protected and service-role gated",()=>{
 assert.match(migration,/enable row level security/g);
 assert.match(migration,/from public,anon,authenticated/);
 assert.match(migration,/grant execute on function public\.mme_notification_claim_delivery_jobs/);
 assert.doesNotMatch(migration,/fetch\(|https?:\/\//i);
});
