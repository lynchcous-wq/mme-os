import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const sql = await readFile(new URL("../supabase/migrations/20261105001100_build009_pos_chargeback_dispute_intelligence.sql", import.meta.url), "utf8");


test("dispute schema includes lifecycle, webhook inbox, evidence, packets, actions and audit", () => {
 for (const table of ["mme_pos_payment_disputes","mme_pos_dispute_events","mme_pos_dispute_evidence","mme_pos_dispute_packets","mme_pos_dispute_actions","mme_pos_dispute_audit_events"]) {
  assert.match(sql,new RegExp("create table public\\."+table));
  assert.match(sql,new RegExp("alter table public\\."+table+" enable row level security"));
 }
});
test("provider event intake is idempotent", () => {
 assert.match(sql,/unique\(provider,provider_event_reference\)/);
 assert.match(sql,/on conflict\(provider,provider_event_reference\) do nothing/);
});
test("response deadline and provider references are modeled", () => {
 assert.match(sql,/response_due_at timestamptz/);
 assert.match(sql,/provider_dispute_reference/);
 assert.match(sql,/provider_payment_reference/);
});
test("evidence packets are versioned, integrity checked and independently approved", () => {
 assert.match(sql,/unique\(dispute_id,packet_version\)/);
 assert.match(sql,/packet_digest_sha256/);
 assert.match(sql,/p_approver_person_id=v_packet.generated_by_person_id/);
 assert.match(sql,/validation_results\)>0/);
});
test("dispute operations enforce role and location authorization", () => {
 for (const p of ["pos.disputes.view","pos.disputes.manage","pos.disputes.evidence","pos.disputes.approve","pos.disputes.submit"]) assert.ok(sql.includes("'" + p + "'"));
 assert.match(sql,/employee_access_frozen/);
 assert.match(sql,/employment_status/);
 assert.match(sql,/scope->>'location_id'/);
});
test("provider submission is not falsely claimed as implemented", () => {
 assert.match(sql,/approved_to_submit/);
 assert.doesNotMatch(sql,/http_post|fetch\(|net\.http_post/i);
 assert.match(sql,/trusted provider adapter/);
});
test("direct client access is revoked and RPC execution restricted", () => {
 assert.match(sql,/from public,anon,authenticated/);
 assert.match(sql,/to service_role/);
});
