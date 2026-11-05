import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync("app/api/employee/inventory/inspection/resolve/route.ts", "utf8");

test("inspection resolution invokes Build 004 approval and resolution authorization", () => {
  assert.match(source, /authenticateAndAuthorizeEmployee/);
  assert.match(source, /"inventory\\.inspection",\\s*actionKey/);
  assert.match(source, /\["approve", "resolve"\]/);
});

test("authorization scope comes from the trusted inspection row", () => {
  assert.match(source, /select: "id,product_id,location_id,serialized_unit_id,disposition"/);
  assert.match(source, /product_id: record\\.product_id/);
  assert.match(source, /location_id: record\\.location_id/);
  assert.doesNotMatch(source, /input\\.(product_id|location_id)/);
});

test("Auth subject maps to a distinct Build 004 person identity", () => {
  assert.match(source, /auth_user_id: `eq\\.\\$\\{user\\.id\\}`/);
  assert.match(source, /p_actor_identity_id: actorIdentityId/);
  assert.match(source, /p_approved_by_identity_id: actorIdentityId/);
  assert.doesNotMatch(source, /p_actor_identity_id: user\\.id/);
});

test("legacy approval and resolution permissions remain as dual checks", () => {
  assert.match(source, /mme_employee_authorize_inventory_action/);
  assert.match(source, /inventory\\.inspection\\.approve/);
  assert.match(source, /inventory\\.inspection\\.resolve/);
});

test("resolution database RPC remains the final transactional authority", () => {
  assert.match(source, /mme_resolve_serialized_inspection/);
  assert.match(source, /mme_resolve_aggregate_inspection/);
});
