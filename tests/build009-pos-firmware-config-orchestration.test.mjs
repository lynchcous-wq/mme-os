import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105001050_build009_pos_firmware_configuration_orchestration.sql", import.meta.url), "utf8");

test("firmware packages require SHA-256 metadata and verified signatures before deployment", () => {
  assert.match(sql, /artifact_sha256 text not null check\(artifact_sha256 ~ '\^\[a-f0-9\]\{64\}\$'\)/);
  assert.match(sql, /signature_storage_key text not null/);
  assert.match(sql, /signature_verified boolean not null default false/);
  assert.match(sql, /status='verified' and signature_verified=true/);
});

test("configuration templates are versioned, digest-bound and approved", () => {
  assert.match(sql, /mme_pos_configuration_templates/);
  assert.match(sql, /unique\(template_key,version_number\)/);
  assert.match(sql, /configuration_digest/);
  assert.match(sql, /status='approved'/);
});

test("campaigns validate target set, device state, model compatibility and location scope", () => {
  assert.match(sql, /cardinality\(p_device_ids\)/);
  assert.match(sql, /One or more deployment devices do not exist/);
  assert.match(sql, /Every campaign device must be online and non-retired/);
  assert.match(sql, /Firmware package is incompatible with a selected device/);
  assert.match(sql, /Configuration template is incompatible with a selected device/);
  assert.match(sql, /Deployment permission denied for one or more device locations/);
});

test("deployment approval is independent, expiring and scoped to every target location", () => {
  assert.match(sql, /mme_pos_deployment_approvals/);
  assert.match(sql, /Requester cannot approve own deployment/);
  assert.match(sql, /v\.expires_at<=now\(\)/);
  assert.match(sql, /not public\.mme_pos_authorize_hardware_action\(p_actor_person_id,'pos\.hardware\.approve',d\.location_id\)/);
});

test("preflight requires recent idle and compatibility verification", () => {
  assert.match(sql, /p_idle_verified is distinct from true/);
  assert.match(sql, /p_compatibility_verified is distinct from true/);
  assert.match(sql, /p_verification_at<now\(\)-interval '2 minutes'/);
  assert.match(sql, /p_verification_at>now\(\)\+interval '30 seconds'/);
  assert.match(sql, /mme_pos_authorize_deployment_dispatch/);
});

test("failed or uncertain deployment targets pause staged rollout", () => {
  assert.match(sql, /status in \('failed','uncertain'\)/);
  assert.match(sql, /Configured failure-rate threshold exceeded/);
  assert.match(sql, /set status='blocked'/);
});

test("recovery is separate, approved and never assumes vendor rollback support", () => {
  assert.match(sql, /vendor_support_verified must be verified/);
  assert.match(sql, /Verified previous firmware package is required/);
  assert.match(sql, /mme_pos_decide_deployment_recovery/);
  assert.match(sql, /Recovery must be pending and approved by a different person/);
  assert.match(sql, /Recovery requires separate approval/);
  assert.match(sql, /pending_approval/);
});

test("new tables use RLS and all privileged functions are service-role only", () => {
  for (const table of ["mme_pos_firmware_packages","mme_pos_configuration_templates","mme_pos_deployment_campaigns","mme_pos_deployment_targets","mme_pos_deployment_events","mme_pos_deployment_approvals","mme_pos_deployment_recovery"]) {
    assert.match(sql, new RegExp("alter table public\\." + table + " enable row level security"));
  }
  for (const fn of ["mme_pos_create_deployment_campaign","mme_pos_decide_deployment_approval","mme_pos_record_deployment_preflight","mme_pos_authorize_deployment_dispatch","mme_pos_pause_deployment_on_failure","mme_pos_request_deployment_recovery","mme_pos_decide_deployment_recovery"]) {
    assert.ok(sql.includes("revoke all on function public." + fn));
    assert.ok(sql.includes("grant execute on function public." + fn));
  }
});
