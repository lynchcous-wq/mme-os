import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/migrations/20261105001070_build009_pos_disaster_recovery_continuity.sql", import.meta.url), "utf8");

test("recovery incident, plan, execution and independent approval lifecycle are modeled", () => {
  for (const table of ["mme_pos_disaster_incidents","mme_pos_recovery_plans","mme_pos_recovery_executions","mme_pos_recovery_approvals","mme_pos_recovery_verification"]) assert.match(sql, new RegExp("create table public\\." + table));
  assert.match(sql, /Requester cannot approve own campaign/); // firmware workflow regression guard
  assert.match(sql, /self-approval was attempted/);
  assert.match(sql, /Recovery execution lacks independent approval/);
});

test("continuity journal is idempotent and prevents unconfirmed payments from completing sales", () => {
  assert.match(sql, /unique\(location_id,register_reference,transaction_reference\)/);
  assert.match(sql, /unique\(idempotency_key\)/);
  assert.match(sql, /Idempotency key reused for a different transaction/);
  assert.match(sql, /Unconfirmed payment cannot complete a sale/);
  assert.match(sql, /Captured sale requires confirmed captured payment state/);
  assert.match(sql, /Never store PAN, CVV, PIN/);
});

test("backup registry records integrity, encryption-key references and restoration verification", () => {
  assert.match(sql, /checksum_sha256/);
  assert.match(sql, /encryption_key_reference/);
  assert.match(sql, /storage_object_reference/);
  assert.match(sql, /restore_test/);
  assert.match(sql, /verification_status/);
});

test("recovery request and approval require separate authorized actors", () => {
  assert.match(sql, /mme_pos_request_recovery_execution/);
  assert.match(sql, /mme_pos_decide_recovery_approval/);
  assert.match(sql, /v.requested_by_person_id=p_actor_person_id/);
  assert.match(sql, /expires_at<=now\(\)/);
  assert.match(sql, /mme_pos_start_recovery_execution/);
});

test("recovery cannot close until verification evidence passes", () => {
  assert.match(sql, /verification_status not in \('passed'\)/);
  assert.match(sql, /blocked_verification_incomplete/);
  assert.match(sql, /succeeded_monitoring/);
});

test("RTO/RPO examples are seeded as drafts, not falsely approved commitments", () => {
  for (const key of ["payment-reconciliation-core","pos-transaction-service","inventory-service","identity-service","executive-dashboard","marketing-platform"]) assert.ok(sql.includes("'" + key + "'"));
  assert.match(sql, /'draft'/);
});

test("all recovery and continuity tables enable RLS and restrict client access", () => {
  for (const table of ["mme_pos_disaster_incidents","mme_pos_recovery_plans","mme_pos_recovery_executions","mme_pos_recovery_approvals","mme_pos_transaction_journal","mme_pos_continuity_events","mme_pos_backup_registry","mme_pos_backup_verifications","mme_pos_recovery_verification"]) {
    assert.match(sql, new RegExp("alter table public\\." + table + " enable row level security"));
  }
  assert.match(sql, /from public,anon,authenticated/);
  assert.match(sql, /to service_role/);
});
