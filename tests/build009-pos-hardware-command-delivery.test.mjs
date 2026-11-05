import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105001000_build009_pos_hardware_command_delivery.sql", import.meta.url), "utf8");

test("command delivery schema persists bounded attempts, retry time, and paired leases", () => {
  assert.ok(sql.includes("dispatch_attempt_count integer not null default 0"));
  assert.ok(sql.includes("dispatch_max_attempts integer not null default 5"));
  assert.ok(sql.includes("next_attempt_at timestamptz not null default now()"));
  assert.ok(sql.includes("dispatch_lease_token uuid"));
  assert.ok(sql.includes("dispatch_lease_until timestamptz"));
  assert.ok(sql.includes("mme_pos_hw_command_lease_pair"));
});

test("command intent reuses only an identical idempotency key binding", () => {
  assert.ok(sql.includes("on conflict(idempotency_key) do nothing returning id into v_id"));
  assert.ok(sql.includes("v_existing.device_id<>p_device_id"));
  assert.ok(sql.includes("v_existing.drawer_session_id is distinct from p_drawer_session_id"));
  assert.ok(sql.includes("v_existing.requested_by_person_id<>p_actor_person_id"));
  assert.ok(sql.includes("v_existing.command_type<>p_command_type"));
});

test("worker claims use row locks with skip locked and bounded leases", () => {
  assert.ok(sql.includes("for update skip locked"));
  assert.ok(sql.includes("p_limit not between 1 and 50"));
  assert.ok(sql.includes("p_lease_seconds not between 10 and 300"));
  assert.ok(sql.includes("dispatch_lease_token=gen_random_uuid()"));
  assert.ok(sql.includes("dispatch_attempt_count=c.dispatch_attempt_count+1"));
});

test("delivery completion requires the matching lease token and schedules bounded retries", () => {
  assert.ok(sql.includes("c.dispatch_lease_token=p_lease_token"));
  assert.ok(sql.includes("c.dispatch_attempt_count>=c.dispatch_max_attempts"));
  assert.ok(sql.includes("now()+make_interval(secs=>p_retry_seconds)"));
  assert.ok(sql.includes("dispatch_lease_token=null,dispatch_lease_until=null"));
  assert.ok(sql.includes("p_retry_seconds not between 1 and 3600"));
});

test("queue claim and finish RPCs are service-role only", () => {
  assert.ok(sql.includes("revoke all on function public.mme_pos_claim_hardware_commands(integer,integer) from public,anon,authenticated"));
  assert.ok(sql.includes("grant execute on function public.mme_pos_claim_hardware_commands(integer,integer) to service_role"));
  assert.ok(sql.includes("revoke all on function public.mme_pos_finish_hardware_command_delivery"));
  assert.ok(sql.includes("grant execute on function public.mme_pos_finish_hardware_command_delivery"));
});
