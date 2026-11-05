import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105001090_build009_pos_fraud_anomaly_intelligence.sql", import.meta.url), "utf8");

test("fraud schema covers rules, events, assessments, cases, evidence, reviews and outcomes", () => {
  for (const table of ["mme_pos_fraud_rules","mme_pos_fraud_events","mme_pos_fraud_assessments","mme_pos_fraud_cases","mme_pos_fraud_case_events","mme_pos_fraud_evidence","mme_pos_fraud_reviews","mme_pos_fraud_outcomes","mme_pos_fraud_audit_events"]) {
    assert.match(sql, new RegExp("create table public\\." + table));
    assert.match(sql, new RegExp("alter table public\\." + table + " enable row level security"));
  }
});

test("fraud event ingestion is idempotent, location scoped and rejects cardholder data", () => {
  assert.match(sql, /on conflict\(event_key\) do nothing/);
  assert.match(sql, /Fraud event key reused across locations/);
  assert.match(sql, /PAN\|card_number\|full_card_number\|cvv\|cvc\|pin\|track_data\|magstripe/);
  assert.match(sql, /processor_reference_token/);
});

test("fraud assessments preserve explainability and versioned risk scoring", () => {
  assert.match(sql, /risk_score integer not null check\(risk_score between 0 and 100\)/);
  assert.match(sql, /contributing_factors jsonb/);
  assert.match(sql, /model_or_ruleset_version/);
  assert.match(sql, /A score is not proof/);
});

test("case creation checks location ownership of linked event and authorized role", () => {
  assert.match(sql, /pos\.fraud\.case\.manage/);
  assert.match(sql, /Fraud event does not belong to case location/);
  assert.match(sql, /fraud_case_created/);
});

test("human review and final outcome are separately recorded and audited", () => {
  assert.match(sql, /pos\.fraud\.review/);
  assert.match(sql, /pos\.fraud\.override/);
  assert.match(sql, /mme_pos_fraud_reviews/);
  assert.match(sql, /mme_pos_fraud_outcomes/);
  assert.match(sql, /fraud_case_reviewed/);
  assert.match(sql, /fraud_outcome_finalized/);
});

test("rules cannot be enabled without explicit approval", () => {
  assert.match(sql, /enabled=false or \(approved_by_person_id is not null and approved_at is not null\)/);
  assert.match(sql, /where id=p_rule_id and enabled=true/);
});

test("direct client access is revoked and fraud RPCs are service-role only", () => {
  assert.match(sql, /from public,anon,authenticated/);
  assert.match(sql, /to service_role/);
  assert.match(sql, /revoke all on function public\.mme_pos_ingest_fraud_event/);
  assert.match(sql, /grant execute on function public\.mme_pos_finalize_fraud_outcome/);
});
