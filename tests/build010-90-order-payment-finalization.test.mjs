import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261107009000_build010_order_payment_finalization.sql", import.meta.url), "utf8");

test("payment finalization records provider event IDs idempotently", () => {
  assert.match(sql, /unique|on conflict \(provider, provider_event_id\) do nothing/i);
  assert.match(sql, /if v_event_id is null then\s+return 'duplicate'/i);
});

test("payment finalization validates exact amount and USD currency", () => {
  assert.match(sql, /v_order\.total_cents <> p_amount_received_cents/);
  assert.match(sql, /v_order\.currency <> 'USD'/);
});

test("successful aggregate payment consumes reserved inventory atomically", () => {
  assert.match(sql, /on_hand_quantity = on_hand_quantity - v_line\.quantity/);
  assert.match(sql, /reserved_quantity = reserved_quantity - v_line\.quantity/);
  assert.match(sql, /status = 'consumed'/);
  assert.match(sql, /status = 'paid'/);
});

test("payment failure or expiry releases aggregate inventory reservations", () => {
  assert.match(sql, /checkout\.session\.async_payment_failed/);
  assert.match(sql, /checkout\.session\.expired/);
  assert.match(sql, /reserved_quantity = reserved_quantity - v_line\.quantity/);
  assert.match(sql, /status = 'payment_failed'/);
  assert.match(sql, /status = 'expired'/);
});

test("RPC is restricted to the trusted service role", () => {
  assert.match(sql, /revoke all .* from public, anon, authenticated/i);
  assert.match(sql, /grant execute .* to service_role/i);
});
