import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105001080_build009_pos_security_intelligence.sql", import.meta.url), "utf8");

test("security intelligence schema includes rules, events, alerts, risk, incidents and investigations", () => {
  for (const table of ["mme_pos_security_rules","mme_pos_security_events","mme_pos_security_alerts","mme_pos_security_risk_scores","mme_pos_security_incidents","mme_pos_security_incident_alerts","mme_pos_security_evidence","mme_pos_security_actions","mme_pos_security_investigations","mme_pos_security_audit_events"]) {
    assert.match(sql, new RegExp("create table public\\." + table));
    assert.match(sql, new RegExp("alter table public\\." + table + " enable row level security"));
  }
});

test("event ingestion is idempotent, validates timestamps and scopes event keys to location", () => {
  assert.match(sql, /unique/);
  assert.match(sql, /p_observed_at>now\(\)\+interval '5 minutes'/);
  assert.match(sql, /on conflict\(event_key\) do nothing/);
  assert.match(sql, /Event key reused across locations/);
});

test("rules must be explicitly approved before activation", () => {
  assert.match(sql, /enabled=false or \(approved_by_person_id is not null and approved_at is not null\)/);
  assert.match(sql, /where id=p_rule_id and enabled=true/);
});

test("alerts retain explainable risk and version references", () => {
  assert.match(sql, /risk_score integer check\(risk_score between 0 and 100\)/);
  assert.match(sql, /explanation text not null/);
  assert.match(sql, /rule_version/);
  assert.match(sql, /occurrence_count=occurrence_count\+1/);
});

test("containment actions require independent approval and preserve audit events", () => {
  assert.match(sql, /pending_approval/);
  assert.match(sql, /requester attempted self-approval/);
  assert.match(sql, /security_action_requested/);
  assert.match(sql, /security_action_'\|\|p_decision/);
});

test("evidence records preserve digest, collection time and custody metadata", () => {
  assert.match(sql, /digest_sha256/);
  assert.match(sql, /collected_at timestamptz not null/);
  assert.match(sql, /chain_of_custody/);
  assert.match(sql, /retention_until/);
});

test("direct client access is revoked and only service role receives table and RPC access", () => {
  assert.match(sql, /from public,anon,authenticated/);
  assert.match(sql, /to service_role/);
  assert.match(sql, /revoke all on function public\\.mme_pos_ingest_security_event/);
  assert.match(sql, /grant execute on function public\\.mme_pos_approve_security_action/);
});

test("security schema explicitly avoids treating alerts as autonomous containment", () => {
  assert.match(sql, /does not autonomously isolate devices/);
  assert.match(sql, /approved response intent only/);
});

test("shared hardware authorization gate retains identity protections and recognizes security permissions", async () => {
  const authSql = await readFile(new URL("../supabase/migrations/20261105001080_build009_pos_security_intelligence.sql", import.meta.url), "utf8");
  for (const permission of ["pos.security.view","pos.security.manage","pos.security.investigate","pos.security.contain","pos.security.rules.manage"]) {
    assert.ok(authSql.includes("'" + permission + "'"));
  }
  assert.match(authSql, /employee_access_frozen/);
  assert.match(authSql, /employment_status/);
  assert.match(authSql, /expires_at is null or g\.expires_at>now\(\)/);
  assert.match(authSql, /scope->>'location_id'/);
});
