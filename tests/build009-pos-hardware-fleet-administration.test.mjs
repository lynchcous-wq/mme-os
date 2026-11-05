import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105001040_build009_pos_hardware_fleet_administration.sql", import.meta.url), "utf8");

test("fleet registry adds bounded hardware identity and warranty metadata", () => {
  assert.match(sql, /add column manufacturer text/);
  assert.match(sql, /add column model text/);
  assert.match(sql, /add column serial_number text/);
  assert.match(sql, /add column firmware_version text/);
  assert.match(sql, /add column adapter_version text/);
  assert.match(sql, /add column warranty_expires_at date/);
  assert.match(sql, /mme_pos_hardware_serial_unique/);
});

test("device assignment preserves history and permits only one active assignment", () => {
  assert.match(sql, /create table public\.mme_pos_device_assignments/);
  assert.match(sql, /mme_pos_device_one_active_assignment/);
  assert.match(sql, /where unassigned_at is null/);
  assert.match(sql, /unassigned_at=now\(\)/);
  assert.match(sql, /mme_pos_device_lifecycle_events/);
});

test("sensitive administration requires a separate non-self approval", () => {
  assert.match(sql, /mme_pos_request_device_admin_approval/);
  assert.match(sql, /mme_pos_decide_device_admin_approval/);
  assert.match(sql, /Requester cannot approve their own hardware administration request/);
  assert.match(sql, /v\.status<>'pending' or v\.expires_at<=now\(\)/);
  assert.match(sql, /pos\.hardware\.approve/);
});

test("reassignment requires an approved request and checks both location scopes", () => {
  assert.match(sql, /mme_pos_assign_hardware_device/);
  assert.match(sql, /Approved reassignment request is required/);
  assert.match(sql, /v_approval.payload/);
  assert.match(sql, /register_reference/);
  assert.match(sql, /v_approval.expires_at<=now\\(\\)/);
  assert.match(sql, /pos\.hardware\.assign',v_device\.location_id/);
  assert.match(sql, /pos\.hardware\.assign',p_location_id/);
});

test("lifecycle transitions are approved, reasoned and recorded", () => {
  assert.match(sql, /mme_pos_set_hardware_device_lifecycle/);
  assert.match(sql, /Approved lifecycle request is required/);
  assert.match(sql, /p_new_status='retired' and v_approval.action_type<>'retire'/);
  assert.match(sql, /p_new_status='maintenance' and v_approval.action_type<>'maintenance'/);
  assert.match(sql, /retired_at=case when p_new_status='retired'/);
  assert.match(sql, /insert into public\.mme_pos_device_lifecycle_events/);
});

test("configuration is versioned and approval does not dispatch it", () => {
  assert.match(sql, /mme_pos_device_configuration_versions/);
  assert.match(sql, /configuration_digest text not null check\(configuration_digest ~ '\^\[a-f0-9\]\{64\}\$'\)/);
  assert.match(sql, /approved_pending_deployment/);
  assert.match(sql, /application remains a separate verified deployment operation/);
});

test("new fleet tables are RLS protected and functions service-role only", () => {
  for (const table of ["mme_pos_device_assignments","mme_pos_device_lifecycle_events","mme_pos_device_configuration_versions","mme_pos_device_admin_approvals","mme_pos_device_admin_actions"]) {
    assert.match(sql, new RegExp("alter table public\\." + table + " enable row level security"));
  }
  assert.match(sql, /from public,anon,authenticated/);
  for (const fn of ["mme_pos_request_device_admin_approval","mme_pos_decide_device_admin_approval","mme_pos_assign_hardware_device","mme_pos_set_hardware_device_lifecycle","mme_pos_propose_hardware_configuration","mme_pos_approve_hardware_configuration"]) {
    assert.ok(sql.includes("revoke all on function public." + fn));
    assert.ok(sql.includes("grant execute on function public." + fn));
  }
});

test("permissions continue to honor active identity, active employment and CEO freeze", () => {
  assert.match(sql, /lifecycle_status into v_person_status/);
  assert.match(sql, /employee_access_frozen/);
  assert.match(sql, /employment_status/);
  assert.match(sql, /v_frozen is distinct from false/);
  assert.match(sql, /revoked_at is null/);
});
