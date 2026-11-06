import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261106002140_build010_notification_provider_receipt_ledger_integrity.sql", import.meta.url), "utf8");

test("receipt ledger has durable event identity and idempotency", () => {
  assert.match(sql, /create table if not exists public\.mme_security_notification_provider_receipt_events/);
  assert.match(sql, /unique index if not exists mme_security_notification_provider_receipt_event_uq/);
  assert.match(sql, /on conflict\(provider,provider_event_id\) do nothing/);
  assert.match(sql, /result','duplicate/);
});

test("receipt ledger is private and ingestion is service-role only", () => {
  assert.match(sql, /enable row level security/);
  assert.match(sql, /revoke all on public\.mme_security_notification_provider_receipt_events from public, anon, authenticated/);
  assert.match(sql, /grant execute on function public\.mme_security_notification_ingest_provider_receipt[\s\S]*to service_role/);
});

test("correlation never guesses between missing or duplicate provider references", () => {
  assert.match(sql, /match_count=0/);
  assert.match(sql, /processing_status='unmatched'/);
  assert.match(sql, /match_count>1/);
  assert.match(sql, /processing_status='ambiguous'/);
});

test("provider receipt event and reference fields are validated before persistence", () => {
  assert.match(sql, /length\(p_event_id\)>250/);
  assert.match(sql, /length\(p_reference\)>500/);
  assert.match(sql, /invalid_provider_receipt/);
});

test("late provider failures cannot downgrade a delivered channel", () => {
  assert.match(sql, /if d\.status='delivered' then/);
  assert.match(sql, /mapped := 'delivered'/);
  assert.match(sql, /processed_terminal_preserved/);
});

test("receipt processing reconciles parent dispatch only after every channel is terminal", () => {
  assert.match(sql, /bool_and\(status in \('delivered','accepted','dead_letter','skipped'\)\)/);
  assert.match(sql, /mme_security_notification_escalation_dispatch_events/);
  assert.match(sql, /mme_security_notification_acknowledgement_escalations/);
});
