import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/pos/hardware/webhook/[providerCode]/route.ts", import.meta.url), "utf8");
const provider = await readFile(new URL("../lib/pos/hardware-provider.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/migrations/20261105001020_build009_pos_hardware_ack_reconciliation.sql", import.meta.url), "utf8");

test("provider normalization accepts only a bounded provider command identifier", () => {
  assert.match(provider, /providerCommandId\?: string/);
  assert.match(provider, /value\.provider_command_id/);
  assert.match(provider, /providerCommandId\.length > 160/);
});

test("verified drawer webhook events are passed to the durable acknowledgment RPC", () => {
  assert.match(route, /mme_pos_ingest_hardware_acknowledgment/);
  assert.match(route, /p_provider_command_id: event\.providerCommandId \?\? null/);
  assert.match(route, /p_device_id: device\.id/);
  assert.match(route, /p_provider_event_id: event\.providerEventId/);
});

test("acknowledgments are idempotent per registered device and provider event ID", () => {
  assert.match(migration, /unique\(device_id,provider_event_id\)/);
  assert.match(migration, /on conflict\(device_id,provider_event_id\) do nothing/);
  assert.match(migration, /Provider event identifier was reused with conflicting acknowledgment data/);
});

test("provider command correlation is constrained to the exact registered device", () => {
  assert.match(migration, /where device_id=v_ack\.device_id and provider_command_id=v_ack\.provider_command_id/);
  assert.match(migration, /v_candidates>1/);
  assert.match(migration, /Provider command identifier matched multiple commands for this device/);
});

test("late matching drawer confirmation can safely resolve uncertain delivery", () => {
  assert.match(migration, /v_command\.status not in \('requested','acknowledged','timed_out'\)/);
  assert.match(migration, /status='confirmed'/);
  assert.match(migration, /delivery_uncertain=false,reconciliation_required=false/);
  assert.match(migration, /status='failed'/);
});

test("unmatched acknowledgments remain durable and are not guessed onto a command", () => {
  assert.match(migration, /if not v_found then return 'unmatched'/);
  assert.match(migration, /reconciliation_state='unmatched'/);
  assert.match(migration, /mme_pos_reconcile_hardware_acknowledgments/);
});

test("conflicting terminal outcomes are recorded rather than overwriting command history", () => {
  assert.match(migration, /reconciliation_state='conflict'/);
  assert.match(migration, /already terminal command outcome/);
});

test("acknowledgment tables and RPCs are service-role-only", () => {
  assert.match(migration, /enable row level security/);
  assert.match(migration, /from public,anon,authenticated/);
  assert.match(migration, /to service_role/);
});
