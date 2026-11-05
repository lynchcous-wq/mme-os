import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105000940_build009_pos_refund_void_controls.sql", import.meta.url), "utf8");

test("Refund and void requests are durable, scoped and idempotent", () => {
  assert.ok(sql.includes("create table public.mme_pos_refund_requests"));
  assert.ok(sql.includes("unique(tender_attempt_id,idempotency_key)"));
  assert.ok(sql.includes("Refund idempotency key reused with different request"));
  assert.ok(sql.includes("Refund exceeds remaining captured balance"));
  assert.ok(sql.includes("Only an uncaptured authorization can be voided"));
});

test("Refund requests require a separate approver", () => {
  assert.ok(sql.includes("approved_by_person_id <> requested_by_person_id"));
  assert.ok(sql.includes("Refund requester cannot approve their own request"));
  assert.ok(sql.includes("pos.refund.approve"));
  assert.ok(sql.includes("case when p_request_type='void' then 'pos.tender.void'"));
});

test("Refund dispatch uses bounded leases and retry limits", () => {
  assert.ok(sql.includes("for update skip locked"));
  assert.ok(sql.includes("lease_token=gen_random_uuid()"));
  assert.ok(sql.includes("r.attempts < 8"));
  assert.ok(sql.includes("max_attempts_exceeded"));
});

test("Only trusted provider outcomes update captured refund totals", () => {
  assert.ok(sql.includes("Successful refund requires provider references"));
  assert.ok(sql.includes("v_new_refunded > v_attempt.captured_amount_minor"));
  assert.ok(sql.includes("status=v_new_status"));
  assert.ok(sql.includes("unknown_reconciliation"));
});

test("Refund RPCs are restricted to the trusted service role", () => {
  for (const fn of [
    "mme_pos_request_refund_or_void",
    "mme_pos_decide_refund_request",
    "mme_pos_claim_refund_dispatch",
    "mme_pos_finish_refund_dispatch"
  ]) {
    assert.ok(sql.includes("revoke all on function public." + fn));
    assert.ok(sql.includes("grant execute on function public." + fn));
  }
});
