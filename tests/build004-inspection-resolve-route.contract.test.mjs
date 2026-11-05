import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync("app/api/employee/inventory/inspection/resolve/route.ts", "utf8");

test("inspection resolution invokes Build 004 approval and resolution authorization", () => {
  assert.ok(source.includes("authenticateAndAuthorizeEmployee"));
  assert.ok(source.includes('"inventory.inspection"'));
  assert.ok(source.includes('["approve", "resolve"]'));
  assert.ok(source.includes("actionKey"));
});

test("authorization scope comes from the trusted inspection row", () => {
  assert.ok(source.includes('select: "id,product_id,location_id,serialized_unit_id,disposition"'));
  assert.ok(source.includes("product_id: record.product_id"));
  assert.ok(source.includes("location_id: record.location_id"));
  assert.ok(!source.includes("input.product_id"));
  assert.ok(!source.includes("input.location_id"));
});

test("Auth subject maps to a distinct Build 004 person identity", () => {
  assert.ok(source.includes("auth_user_id: `eq.${user.id}`"));
  assert.ok(source.includes("p_actor_identity_id: actorIdentityId"));
  assert.ok(source.includes("p_approved_by_identity_id: actorIdentityId"));
  assert.ok(!source.includes("p_actor_identity_id: user.id"));
});

test("legacy approval and resolution permissions remain as dual checks", () => {
  assert.ok(source.includes("mme_employee_authorize_inventory_action"));
  assert.ok(source.includes("inventory.inspection.approve"));
  assert.ok(source.includes("inventory.inspection.resolve"));
});

test("resolution database RPC remains the final transactional authority", () => {
  assert.ok(source.includes("mme_resolve_serialized_inspection"));
  assert.ok(source.includes("mme_resolve_aggregate_inspection"));
});
