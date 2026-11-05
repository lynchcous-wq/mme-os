import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync("app/api/employee/inventory/inspection/route.ts", "utf8");

test("inspection submission invokes the server-only Build 004 authorization helper", () => {
  assert.match(source, /authenticateAndAuthorizeEmployee/);
  assert.match(source, /"inventory\.inspection",\s*"submit"/);
});

test("authorization scope is derived from the matched serialized-unit database row", () => {
  assert.match(source, /select: "id,product_id,location_id"/);
  assert.match(source, /product_id:\s*unit\.product_id/);
  assert.match(source, /location_id:\s*unit\.location_id/);
  assert.doesNotMatch(source, /body\.(product_id|location_id)/);
});

test("person identity is resolved from the validated Auth subject, not assumed equal", () => {
  assert.match(source, /auth_user_id:\s*`eq\.\$\{actorUserId\}`/);
  assert.match(source, /p_actor_identity_id:\s*identityResult\.data\[0\]\.id/);
  assert.doesNotMatch(source, /p_actor_identity_id:\s*actorUserId/);
});

test("legacy transactional submission remains in place as a dual-check", () => {
  assert.match(source, /mme_submit_serialized_inspection/);
  assert.match(source, /p_actor_user_id:\s*actorUserId/);
});
