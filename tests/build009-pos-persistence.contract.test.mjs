import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261105009000_build009_pos_transaction_orchestration.sql", import.meta.url), "utf8");

test("POS persistence reuses Build 001 order and location owners", () => {
  assert.match(migration, /order_id uuid not null references public\.mme_orders/);
  assert.match(migration, /store_id uuid not null references public\.mme_store_locations/);
  assert.match(migration, /unique\s*\(order_id\)/i);
  assert.doesNotMatch(migration, /create table public\.mme_pos_orders/i);
  assert.doesNotMatch(migration, /create table public\.mme_pos_inventory_balances/i);
});

test("Tender allocation records are idempotent and cannot exceed captured refund bounds", () => {
  assert.match(migration, /idempotency_key text not null unique/);
  assert.match(migration, /request_fingerprint text not null/);
  assert.match(migration, /refunded_amount_cents <= captured_amount_cents/);
  assert.match(migration, /unknown_reconciliation/);
});

test("POS event history is append-only and downstream work uses transactional outbox", () => {
  assert.match(migration, /create table public\.mme_pos_transaction_events/i);
  assert.match(migration, /before update or delete on public\.mme_pos_transaction_events/i);
  assert.match(migration, /create table public\.mme_pos_outbox/i);
  assert.match(migration, /unique\(event_id, event_type\)/);
});

test("POS transaction creation checks active person, CEO freeze, and store-scoped permission", () => {
  assert.match(migration, /mme_pos_authorize_register_action/);
  assert.match(migration, /employee_access_frozen/);
  assert.match(migration, /g\.scope ->> 'store_id'/);
  assert.match(migration, /pos\.transaction\.create/);
  assert.match(migration, /revoke all on function public\.mme_pos_create_transaction[\s\S]*?from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function public\.mme_pos_create_transaction[\s\S]*?to service_role/i);
});

test("POS tables deny browser roles and enable RLS", () => {
  for (const table of ["mme_pos_transactions", "mme_pos_tender_allocations", "mme_pos_transaction_events", "mme_pos_outbox"]) {
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`));
    assert.match(migration, new RegExp(`revoke all on public\\.${table} from anon, authenticated`));
  }
});
