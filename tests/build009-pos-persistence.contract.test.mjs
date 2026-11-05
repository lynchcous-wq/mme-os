import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261105000900_build009_pos_transaction_orchestration.sql", import.meta.url), "utf8");

test("POS persistence reuses Build 001 order and active inventory reservation", () => {
  assert.match(migration, /order_id uuid not null unique references public\.mme_orders/);
  assert.match(migration, /public\.mme_inventory_reservations/);
  assert.doesNotMatch(migration, /create table public\.mme_pos_orders/i);
  assert.doesNotMatch(migration, /create table public\.mme_pos_inventory_balances/i);
});

test("POS transaction creation is idempotent, linked to a pending order, and person-authorized", () => {
  assert.match(migration, /mme_person_authorize_pos_action/);
  assert.match(migration, /employee_access_frozen/);
  assert.match(migration, /v_person_status is distinct from 'active'/);
  assert.match(migration, /employment_status is distinct from 'active'/);
  assert.match(migration, /pos\.transaction\.create/);
  assert.match(migration, /POS transaction event permission denied/);
  assert.match(migration, /idempotency_key text not null unique/);
  assert.match(migration, /v_order\.status <> 'pending_payment'/);
  assert.match(migration, /p_order_id or idempotency_key = p_idempotency_key/);
});

test("POS event appends enforce optimistic revision and request idempotency", () => {
  assert.match(migration, /unique \(transaction_id, revision\)/);
  assert.match(migration, /unique \(transaction_id, idempotency_key\)/);
  assert.match(migration, /v_tx\.revision <> p_expected_revision/);
  assert.match(migration, /POS idempotency key reused with different request/);
});

test("POS event payloads reject sensitive payment data and use a durable outbox", () => {
  assert.match(migration, /pan\|card_number\|cvv\|cvc\|pin\|track_data/);
  assert.match(migration, /create table public\.mme_pos_outbox/i);
  assert.match(migration, /transaction_event_id uuid not null unique/);
  assert.match(migration, /grant all on public\.mme_pos_transactions, public\.mme_pos_transaction_events, public\.mme_pos_outbox\s+to service_role/i);
});

test("POS tables enable RLS and browser roles cannot execute privileged functions", () => {
  for (const table of ["mme_pos_transactions", "mme_pos_transaction_events", "mme_pos_outbox"]) {
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`));
  }
  assert.match(migration, /revoke all on function public\.mme_pos_create_transaction[\s\S]*?from public, anon, authenticated/i);
  assert.match(migration, /revoke all on function public\.mme_pos_append_transaction_event[\s\S]*?from public, anon, authenticated/i);
});
