import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105001060_build009_pos_network_connectivity_security.sql", import.meta.url), "utf8");

test("network zones separate payment, POS, peripherals, management and guest access", () => {
  for (const zone of ["pos","payment","peripherals","management","guest","infrastructure"]) assert.match(sql, new RegExp("'" + zone + "'"));
  assert.match(sql, /trust_level text not null/);
});

test("device network inventory records segmentation and transport posture", () => {
  assert.match(sql, /mme_pos_network_devices/);
  assert.match(sql, /vlan_reference/);
  assert.match(sql, /connection_type/);
  assert.match(sql, /security_posture/);
});

test("connection observations require authenticated and encrypted transport", () => {
  assert.match(sql, /p_authenticated is distinct from true or p_encrypted is distinct from true/);
  assert.match(sql, /unauthenticated_peer/);
  assert.match(sql, /unencrypted_session/);
  assert.match(sql, /return null;/);
  assert.match(sql, /Connection did not satisfy authentication and encryption requirements/);
});

test("certificate metadata references external secret storage and supports expiry and revocation", () => {
  assert.match(sql, /certificate_fingerprint_sha256/);
  assert.match(sql, /secret_reference/);
  assert.match(sql, /expires_at timestamptz not null/);
  assert.match(sql, /mme_pos_activate_device_certificate/);
  assert.match(sql, /mme_pos_revoke_device_certificate/);
  assert.match(sql, /signature_validation_reference/);
});

test("network health and incidents preserve timestamped observations", () => {
  assert.match(sql, /mme_pos_network_health/);
  assert.match(sql, /availability_percent/);
  assert.match(sql, /packet_loss_percent/);
  assert.match(sql, /mme_pos_network_incidents/);
  assert.match(sql, /mme_pos_network_failover_events/);
});

test("new network tables use RLS and direct client access is revoked", () => {
  for (const table of ["mme_pos_network_zones","mme_pos_network_devices","mme_pos_network_connections","mme_pos_device_certificates","mme_pos_network_health","mme_pos_network_incidents","mme_pos_network_failover_events","mme_pos_network_security_events"]) {
    assert.match(sql, new RegExp("alter table public\\." + table + " enable row level security"));
    assert.ok(sql.includes("public." + table));
  }
  assert.match(sql, /from public,anon,authenticated/);
  assert.match(sql, /to service_role/);
});

test("network administrative permissions extend the existing identity and employment gate", () => {
  assert.match(sql, /'pos\.network\.view'/);
  assert.match(sql, /'pos\.network\.manage'/);
  assert.match(sql, /'pos\.network\.certificates'/);
  assert.match(sql, /employee_access_frozen/);
  assert.match(sql, /employment_status/);
});
