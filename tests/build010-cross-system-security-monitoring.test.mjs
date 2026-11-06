import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261106002150_build010_cross_system_security_monitoring_snapshots.sql", import.meta.url), "utf8");
const route = await readFile(new URL("../app/api/warranty/security-intelligence/monitoring/route.ts", import.meta.url), "utf8");

test("monitoring snapshots aggregate source health, queues, alerts, and provider receipts", () => {
  assert.match(migration, /mme_security_event_source_health/);
  assert.match(migration, /mme_warranty_security_event_delivery_queue/);
  assert.match(migration, /mme_security_integration_alerts/);
  assert.match(migration, /mme_security_notification_provider_receipt_events/);
  assert.match(migration, /mme_security_notification_escalation_channel_deliveries/);
});

test("snapshot status escalates for critical alerts, dead letters, and offline sources", () => {
  assert.match(migration, /open_critical>0 or dead_count>0/);
  assert.match(migration, /status='offline'/);
  assert.match(migration, /then 'critical'/);
  assert.match(migration, /then 'degraded'/);
});

test("snapshot history is private and service-role controlled", () => {
  assert.match(migration, /enable row level security/);
  assert.match(migration, /revoke all on public\.mme_security_monitoring_snapshots from public,anon,authenticated/);
  assert.match(migration, /grant execute on function public\.mme_security_monitoring_capture_snapshot\(\) to service_role/);
});

test("monitoring endpoint authenticates the user and restricts operational roles", () => {
  assert.match(route, /auth\/v1\/user/);
  assert.match(route, /ceo.*cio.*it_admin.*privacy_officer.*manager/);
  assert.match(route, /security_monitoring_access_denied/);
  assert.match(route, /mme_security_monitoring_capture_snapshot/);
  assert.match(route, /Cache-Control.*no-store/);
});

test("monitoring endpoint never exposes the service role credential to the client", () => {
  assert.match(route, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(route, /NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY/);
});
