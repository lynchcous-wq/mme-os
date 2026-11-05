import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105000950_build009_pos_refund_dispute_reconciliation.sql", import.meta.url), "utf8");

test("Provider refund settlement matching is exact and idempotently linked", () => {
  assert.ok(sql.includes("mme_pos_reconcile_refund_settlement"));
  assert.ok(sql.includes("r.provider_refund_reference=v_record.provider_operation_reference"));
  assert.ok(sql.includes("r.amount_minor=v_record.amount_minor"));
  assert.ok(sql.includes("r.currency=v_record.currency"));
  assert.ok(sql.includes("refund_already_linked_to_other_settlement"));
  assert.ok(sql.includes("mme_pos_refund_settlement_record_unique"));
});

test("Refund reconciliation rejects non-refund and non-completed evidence", () => {
  assert.ok(sql.includes("v_record.record_type <> 'refund'"));
  assert.ok(sql.includes("v_request.status <> 'completed'"));
  assert.ok(sql.includes("no_refund_reference_match"));
  assert.ok(sql.includes("refund_amount_or_currency_mismatch"));
  assert.ok(sql.includes("'pending','matched','mismatch','unmatched','manual_review'"));
  assert.ok(sql.includes("ambiguous_refund_reference_match"));
});

test("Disputes are account-scoped and provider-event idempotent", () => {
  assert.ok(sql.includes("create table public.mme_pos_provider_disputes"));
  assert.ok(sql.includes("create table public.mme_pos_provider_dispute_events"));
  assert.ok(sql.includes("unique(provider,provider_account_reference,provider_dispute_reference)"));
  assert.ok(sql.includes("unique(dispute_id,provider_event_reference)"));
  assert.ok(sql.includes("Provider dispute event reference reused with different event data"));
});

test("Out-of-order provider dispute events cannot roll back newer state", () => {
  assert.ok(sql.includes("latest_provider_event_occurred_at"));
  assert.ok(sql.includes("p_occurred_at >= latest_provider_event_occurred_at"));
  assert.ok(sql.includes("when status='manual_review' then 'manual_review'"));
});

test("Dispute event imports fail closed on invalid values and ambiguous payment links", () => {
  assert.ok(sql.includes("Invalid provider dispute event"));
  assert.ok(sql.includes("or p_occurred_at is null"));
  assert.ok(sql.includes("v_count=1 then v_attempt.id else null end"));
  assert.ok(sql.includes("case when v_count=1 then 'open' else 'manual_review' end"));
  assert.ok(sql.includes("raw_event_digest text not null check(raw_event_digest ~"));
});

test("Refund reconciliation and dispute imports are service-role only", () => {
  for (const fn of ["mme_pos_reconcile_refund_settlement","mme_pos_import_dispute_event"]) {
    assert.ok(sql.includes("revoke all on function public." + fn));
    assert.ok(sql.includes("grant execute on function public." + fn));
  }
});
