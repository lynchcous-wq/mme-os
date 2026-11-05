import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const legacySql = await readFile(
  new URL("../supabase/migrations/20261103000003_catalog_integration_employee_authorization_engine.sql", import.meta.url),
  "utf8",
);
const personSql = await readFile(
  new URL("../supabase/migrations/20261103008440_build004_require_active_person_identity.sql", import.meta.url),
  "utf8",
);

const now = Date.parse("2026-11-05T12:00:00.000Z");

function grantAllows(grants, permission, productId, at = now) {
  return grants.some((grant) =>
    grant.permission === permission &&
    grant.revokedAt == null &&
    (grant.expiresAt == null || Date.parse(grant.expiresAt) > at) &&
    (grant.scope === "global" || grant.productId === productId)
  );
}

// Executable decision model for synthetic fixtures only. It does not connect to
// Supabase or claim to execute the PL/pgSQL functions; source guards below pin
// the model's assumptions to the reviewed SQL definitions.
function legacyDecision(f) {
  if (!f.actorAuthId || f.employmentStatus !== "active" ||
      f.frozen !== false || !f.ceoAuthId) return false;
  if (["catalog.approve", "catalog.publish"].includes(f.permission) &&
      f.submitterAuthId && f.actorAuthId === f.submitterAuthId) return false;
  if (f.actorAuthId === f.ceoAuthId) return true;
  return grantAllows(f.legacyGrants, f.permission, f.productId);
}

function personDecision(f) {
  if (!f.actorPersonId || f.personStatus !== "active" ||
      f.employmentStatus !== "active" || f.frozen !== false ||
      !f.ceoPersonId) return false;
  if (["catalog.approve", "catalog.publish"].includes(f.permission) &&
      (!f.creatorPersonId || f.actorPersonId === f.creatorPersonId)) return false;
  if (f.actorPersonId === f.ceoPersonId) return true;
  return grantAllows(f.personGrants, f.permission, f.productId);
}

function fixture(overrides = {}) {
  return {
    actorAuthId: "auth-employee-1",
    actorPersonId: "person-employee-1",
    personStatus: "active",
    employmentStatus: "active",
    frozen: false,
    ceoAuthId: "auth-ceo",
    ceoPersonId: "person-ceo",
    permission: "catalog.edit",
    productId: "product-1",
    submitterAuthId: null,
    creatorPersonId: null,
    legacyGrants: [{ permission: "catalog.edit", scope: "global" }, { permission: "catalog.approve", scope: "global" }],
    personGrants: [{ permission: "catalog.edit", scope: "global" }, { permission: "catalog.approve", scope: "global" }],
    ...overrides,
  };
}

test("synthetic baseline: equivalent active global grant allows both models", () => {
  const f = fixture();
  assert.equal(legacyDecision(f), true);
  assert.equal(personDecision(f), true);
});

test("synthetic expired and revoked grants deny both models", () => {
  for (const grant of [
    { permission: "catalog.edit", scope: "global", expiresAt: "2026-11-05T11:59:59.000Z" },
    { permission: "catalog.edit", scope: "global", revokedAt: "2026-11-05T11:00:00.000Z" },
  ]) {
    const f = fixture({ legacyGrants: [grant], personGrants: [grant] });
    assert.equal(legacyDecision(f), false);
    assert.equal(personDecision(f), false);
  }
});

test("synthetic company freeze and missing CEO configuration deny both models", () => {
  for (const overrides of [{ frozen: true }, { ceoAuthId: null, ceoPersonId: null }]) {
    const f = fixture(overrides);
    assert.equal(legacyDecision(f), false);
    assert.equal(personDecision(f), false);
  }
});

test("inactive person lifecycle is an intentional person-keyed denial", () => {
  const f = fixture({ personStatus: "locked" });
  assert.equal(legacyDecision(f), true);
  assert.equal(personDecision(f), false);
});

test("legacy caller-omitted submitter can allow self-approval while person model denies mapped creator", () => {
  const f = fixture({
    permission: "catalog.approve",
    submitterAuthId: null,
    creatorPersonId: "person-employee-1",
  });
  assert.equal(legacyDecision(f), true);
  assert.equal(personDecision(f), false);
});

test("unresolved protected creator mapping fails closed in person model", () => {
  const f = fixture({ permission: "catalog.approve", creatorPersonId: null });
  assert.equal(legacyDecision(f), true);
  assert.equal(personDecision(f), false);
});

test("legacy SQL relies on caller submitter; person SQL resolves protected product creator", () => {
  assert.match(legacySql, /p_submitter_user_id uuid default null/);
  assert.match(legacySql, /p_actor_user_id = p_submitter_user_id/);
  assert.match(personSql, /mme_resolve_person_for_auth_subject\(created_by\)/);
  assert.match(personSql, /p_actor_person_id = v_creator_person_id/);
});

test("person SQL enforces active lifecycle, employment, freeze and CEO configuration", () => {
  assert.equal((personSql.match(/v_person_status is distinct from 'active'/g) ?? []).length, 2);
  assert.equal((personSql.match(/v_employment_status is distinct from 'active'/g) ?? []).length, 2);
  assert.equal((personSql.match(/v_frozen is distinct from false or v_ceo_person_id is null/g) ?? []).length, 2);
});

test("this fixture suite explicitly remains a model test, not a live database parity claim", () => {
  assert.match(personSql, /no Auth-UUID fallback/i);
  assert.match(legacySql, /validated identity-provider session/i);
});
