import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const page = await readFile(new URL("../app/employee/workflows/reconciliation/page.tsx", import.meta.url), "utf8");
const route = await readFile(new URL("../app/api/employee/workflows/reconciliation/route.ts", import.meta.url), "utf8");

test("reconciliation UI models decision history", () => {
  assert.match(page, /type ReconciliationDecision/);
  assert.match(page, /decision_history:\s*ReconciliationDecision\[\]/);
  assert.match(page, /Supervisor decision history/);
});
test("decision history displays the recorded outcome, reason, reviewer, time and evidence", () => {
  for (const field of ["decision.outcome","decision.reason","decision.decided_by_user_id","decision.decided_at","decision.evidence_references"]) {
    assert.ok(page.includes(field), "missing " + field);
  }
});
test("decision history is distinct from workflow event history", () => {
  assert.match(page, /Supervisor decision history/);
  assert.match(page, /Audit history/);
  assert.match(page, /item\.audit_history/);
});
test("history loads through authenticated no-store inbox API", () => {
  assert.match(page, /\/api\/employee\/workflows\/reconciliation\?limit=100/);
  assert.match(page, /Authorization:\s*"Bearer "\s*\+\s*token/);
  assert.match(page, /cache:\s*"no-store"/);
  assert.match(route, /\/auth\/v1\/user/);
  assert.match(route, /mme_list_cancelled_workflow_reconciliations/);
});
test("decision history has no edit or delete actions", () => {
  const start = page.indexOf("Supervisor decision history");
  const end = page.indexOf("</details>", start);
  const block = page.slice(start, end);
  assert.doesNotMatch(block, /onClick|onChange|<button|<input/);
});
