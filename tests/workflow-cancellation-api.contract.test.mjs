import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(
  new URL("../app/api/employee/workflows/cancellation/route.ts", import.meta.url),
  "utf8",
);

test("cancellation endpoint requires a bearer session and validates it with Supabase Auth", () => {
  assert.match(route, /authorization.*Bearer/);
  assert.match(route, /\/auth\/v1\/user/);
  assert.match(route, /if \(!auth\.ok\).*401/s);
});

test("actor identity is derived from the verified session, never the request body", () => {
  assert.match(route, /p_actor_user_id:\s*session\.userId/);
  assert.doesNotMatch(route, /input\.actor_user_id|body\.actor_user_id/);
});

test("request rejects non-JSON, oversized bodies, malformed UUIDs, and invalid reasons", () => {
  assert.match(route, /application\/json/);
  assert.match(route, /byteLength\(raw\)\s*>\s*4000/);
  assert.match(route, /executionId.*valid UUID/s);
  assert.match(route, /reason\.trim\(\)\.length < 3/);
  assert.match(route, /reason\.trim\(\)\.length > 1000/);
});

test("privileged cancellation call is server-side and bound to the verified actor", () => {
  assert.match(route, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(route, /rpc\/mme_cancel_workflow_execution/);
  assert.match(route, /p_execution_id:\s*executionId/);
  assert.match(route, /p_reason:\s*reason\.trim\(\)/);
});

test("authorization and terminal-state failures are not reported as success", () => {
  assert.match(route, /if \(!response\.ok\)/);
  assert.match(route, /Cancellation was rejected by workflow authorization or state controls/);
  assert.match(route, /result !== "cancelled"/);
});

test("successful response is private and non-cacheable", () => {
  assert.match(route, /Cache-Control.*no-store, private/);
  assert.match(route, /Vary.*Authorization/);
});
