import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(
  new URL("../app/api/employee/workflows/reconciliation/decision/route.ts", import.meta.url),
  "utf8",
);

test("decision endpoint requires and verifies a Supabase bearer session", () => {
  assert.match(route, /authorization.*Bearer/);
  assert.match(route, /\/auth\/v1\/user/);
  assert.match(route, /if \(!auth\.ok\).*401/s);
  assert.match(route, /SUPABASE_SERVICE_ROLE_KEY/);
});

test("actor identity comes only from the verified Supabase user", () => {
  assert.match(route, /p_actor_user_id:\s*user\.id/);
  assert.match(route, /allowedKeys = new Set\(\["step_run_id", "outcome", "reason", "evidence_references"\]\)/);
  assert.doesNotMatch(route, /body\.actor_user_id|input\.actor_user_id/);
});

test("request content type, size, object shape, and supported keys are constrained", () => {
  assert.match(route, /application\/json/);
  assert.match(route, /byteLength\(raw\)\s*>\s*12000/);
  assert.match(route, /JSON\.parse\(raw\)/);
  assert.match(route, /unsupported fields/);
});

test("step identifier, outcome, and reason are strictly validated", () => {
  assert.match(route, /Number\.isSafeInteger\(stepRunId\)/);
  assert.match(route, /OUTCOMES\.has\(body\.outcome\)/);
  assert.match(route, /reason\.trim\(\)\.length < 3/);
  assert.match(route, /reason\.trim\(\)\.length > 1000/);
});

test("evidence references are bounded and validate opaque reference metadata", () => {
  assert.match(route, /body\.evidence_references\.length < 1/);
  assert.match(route, /body\.evidence_references\.length > 20/);
  assert.match(route, /entry\.kind\.trim\(\)\.length < 2/);
  assert.match(route, /entry\.reference\.trim\(\)\.length > 500/);
  assert.match(route, /\^\[0-9a-f\]\{64\}\$/);
  assert.match(route, /\["kind", "reference", "sha256"\]/);
});

test("privileged RPC receives the verified actor and validated decision payload", () => {
  assert.match(route, /rpc\/mme_record_cancelled_workflow_reconciliation_decision/);
  assert.match(route, /p_step_run_id:\s*stepRunId/);
  assert.match(route, /p_outcome:\s*body\.outcome/);
  assert.match(route, /p_evidence_references:\s*evidence/);
  assert.match(route, /cache: "no-store"/);
});

test("RPC rejection is not represented as a successful decision", () => {
  assert.match(route, /if \(!response\.ok\)/);
  assert.match(route, /decision was rejected by workflow state, evidence, or supervisor authorization controls/);
  assert.match(route, /accepted: true/);
  assert.match(route, /workflow_status_changed: false/);
  assert.match(route, /retry_or_resume_authorized: false/);
});

test("success response is private and non-cacheable", () => {
  assert.match(route, /Cache-Control.*no-store, private/);
  assert.match(route, /Vary.*Authorization/);
});
