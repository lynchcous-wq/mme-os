import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const history = readFileSync("app/api/employee/inventory/inspection/history/route.ts", "utf8");
const photos = readFileSync("app/api/employee/inventory/inspection/photos/route.ts", "utf8");

test("history maps validated Auth subject to person identity before querying ownership", () => {
  assert.ok(history.includes("authenticateAndAuthorizeEmployee"));
  assert.ok(history.includes("auth_user_id: `eq.${user.id}`"));
  assert.ok(history.includes("inspected_by_identity_id: `eq.${actorIdentityId}`"));
  assert.ok(!history.includes("inspected_by_identity_id: `eq.${user.id}`"));
});

test("history checks Build 004 view permission using database-derived product and location", () => {
  assert.ok(history.includes('"inventory.inspection"'));
  assert.ok(history.includes('"view"'));
  assert.ok(history.includes("product_id: String(item.product_id)"));
  assert.ok(history.includes("location_id: String(item.location_id)"));
  assert.ok(history.includes("mme_employee_authorize_inventory_action"));
});

test("photo evidence maps Auth subject to person identity and enforces submitter ownership", () => {
  assert.ok(photos.includes("auth_user_id: `eq.${authUser.id}`"));
  assert.ok(photos.includes("record.inspected_by_identity_id !== actorIdentityId"));
  assert.ok(photos.includes("p_actor_identity_id: actorIdentityId"));
});

test("photo evidence uses Build 004 submit authorization with trusted inspection scope", () => {
  assert.ok(photos.includes("authenticateAndAuthorizeEmployee"));
  assert.ok(photos.includes('"inventory.inspection"'));
  assert.ok(photos.includes('"submit"'));
  assert.ok(photos.includes("product_id: record.product_id"));
  assert.ok(photos.includes("location_id: record.location_id"));
  assert.ok(photos.includes("mme_employee_authorize_inventory_action"));
});

test("private evidence safeguards remain present", () => {
  assert.ok(photos.includes("MAX_BYTES"));
  assert.ok(photos.includes("signatureValid"));
  assert.ok(photos.includes("mme_register_inspection_photo_evidence"));
  assert.ok(photos.includes("Cache-Control"));
});

test("history distinguishes authorization denial from authorization service failure", () => {
  assert.ok(history.includes("if (!permission.ok)"));
  assert.ok(history.includes('status: 503'));
  assert.ok(history.includes("if (await permission.json() === true) authorized.push(item)"));
});

test("photo authorization service outage fails closed separately from a denied permission", () => {
  assert.ok(photos.includes("if (!authorization.ok)"));
  assert.ok(photos.includes('status: 503'));
  assert.ok(photos.includes("if (authorization.data !== true)"));
});
