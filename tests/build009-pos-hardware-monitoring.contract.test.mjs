import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105000970_build009_pos_hardware_monitoring.sql", import.meta.url), "utf8");

test("POS hardware registry is location-bound and supports register device lifecycle", () => {
  assert.ok(sql.includes("mme_pos_register_devices"));
  assert.ok(sql.includes("unique(provider,device_reference)"));
  assert.ok(sql.includes("mme_pos_register_drawer_hardware_device"));
  assert.ok(sql.includes("pos.hardware.register"));
  assert.ok(sql.includes("'cash_drawer','receipt_printer','payment_terminal','register_controller'"));
});

test("Hardware command history records intent and outcome without claiming transport", () => {
  assert.ok(sql.includes("mme_pos_drawer_hardware_commands"));
  assert.ok(sql.includes("mme_pos_record_drawer_hardware_command_intent"));
  assert.ok(sql.includes("requested_by_person_id"));
  assert.ok(sql.includes("idempotency_key"));
  assert.ok(sql.includes("Auditable command intent and provider-reported outcome; not a hardware command transport."));
});

test("Device telemetry is idempotent and records connectivity and drawer events", () => {
  assert.ok(sql.includes("mme_pos_drawer_hardware_events"));
  assert.ok(sql.includes("unique(device_id,provider_event_id)"));
  assert.ok(sql.includes("mme_pos_ingest_drawer_hardware_event"));
  for (const event of ["heartbeat","device_online","device_offline","drawer_open_confirmed","drawer_open_failed","connection_lost","connection_restored"]) assert.ok(sql.includes("'" + event + "'"));
});

test("Drawer failure and post-sale failure create IT incidents", () => {
  assert.ok(sql.includes("mme_pos_drawer_it_incidents"));
  assert.ok(sql.includes("sale_drawer_failure"));
  assert.ok(sql.includes("Sale completed but cash drawer failed to open"));
  assert.ok(sql.includes("drawer_open_failed"));
  assert.ok(sql.includes("device_offline"));
});

test("IT incidents have acknowledgment, assignment, resolution and closure workflow", () => {
  assert.ok(sql.includes("mme_pos_update_drawer_it_incident"));
  for (const status of ["open","acknowledged","in_progress","resolved","closed"]) assert.ok(sql.includes("'" + status + "'"));
  assert.ok(sql.includes("Resolution requires an active incident and a meaningful note"));
});

test("Hardware tables and privileged functions are restricted to service role", () => {
  for (const table of ["mme_pos_register_devices","mme_pos_drawer_hardware_events","mme_pos_drawer_hardware_commands","mme_pos_drawer_it_incidents"]) {
    assert.ok(sql.includes("alter table public." + table + " enable row level security"));
  }
  assert.ok(sql.includes("from public,anon,authenticated"));
  assert.ok(sql.includes("to service_role;"));
  for (const fn of ["mme_pos_register_drawer_hardware_device","mme_pos_record_drawer_hardware_command_intent","mme_pos_ingest_drawer_hardware_event","mme_pos_update_drawer_it_incident"]) {
    assert.ok(sql.includes("revoke all on function public." + fn));
    assert.ok(sql.includes("grant execute on function public." + fn));
  }
});

const supervisionSql = await readFile(new URL("../supabase/migrations/20261105000980_build009_pos_hardware_pairing_supervision.sql", import.meta.url), "utf8");

test("Provider adapter metadata stores external secret references, not raw credentials", () => {
  assert.ok(supervisionSql.includes("mme_pos_hardware_provider_adapters"));
  assert.ok(supervisionSql.includes("credential_secret_ref"));
  assert.ok(supervisionSql.includes("webhook_secret_ref"));
  assert.ok(supervisionSql.includes("never store raw credentials"));
  assert.ok(supervisionSql.includes("from public,anon,authenticated"));
});

test("Pairing challenge is digest-only, short-lived, and one-time", () => {
  assert.ok(supervisionSql.includes("challenge_digest text not null"));
  assert.ok(supervisionSql.includes("^[a-f0-9]{64}$"));
  assert.ok(supervisionSql.includes("p_expires_at>now()+interval '15 minutes'"));
  assert.ok(supervisionSql.includes("consumed_at is null and expires_at>now()"));
  assert.ok(supervisionSql.includes("set consumed_at=now()"));
  assert.ok(supervisionSql.includes("provider_proof_verified is distinct from true"));
});

test("Heartbeat supervision detects stale paired devices and opens an IT incident", () => {
  assert.ok(supervisionSql.includes("mme_pos_sweep_stale_hardware_devices"));
  assert.ok(supervisionSql.includes("last_heartbeat_at"));
  assert.ok(supervisionSql.includes("heartbeat_interval_seconds*3"));
  assert.ok(supervisionSql.includes("set status='offline'"));
  assert.ok(supervisionSql.includes("POS device heartbeat missed"));
  assert.ok(supervisionSql.includes("on conflict(device_id,incident_type)"));
});

test("Heartbeat ingestion records an event and refreshes device health", () => {
  assert.ok(supervisionSql.includes("mme_pos_record_hardware_heartbeat"));
  assert.ok(supervisionSql.includes("mme_pos_ingest_drawer_hardware_event"));
  assert.ok(supervisionSql.includes("last_heartbeat_at=p_occurred_at"));
});

test("New pairing and supervision functions are service-role only", () => {
  for (const fn of ["mme_pos_create_hardware_pairing_challenge","mme_pos_complete_hardware_pairing","mme_pos_sweep_stale_hardware_devices","mme_pos_record_hardware_heartbeat"]) {
    assert.ok(supervisionSql.includes("revoke all on function public." + fn));
    assert.ok(supervisionSql.includes("grant execute on function public." + fn));
  }
});
