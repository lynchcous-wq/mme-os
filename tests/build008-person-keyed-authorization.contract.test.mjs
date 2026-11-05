import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  new URL("../supabase/migrations/20261103008430_build004_person_keyed_authorization.sql", import.meta.url),
  "utf8",
);

test("person-keyed catalog and inventory authorization are separate server-only decision points", () => {
  assert.match(migration, /create function public\.mme_person_authorize_catalog_action\(\s*p_actor_person_id uuid/);
  assert.match(migration, /create function public\.mme_person_authorize_inventory_action\(\s*p_actor_person_id uuid/);
  assert.match(migration, /grant execute on function public\.mme_person_authorize_catalog_action\(uuid,text,uuid\)\s+to service_role/);
  assert.match(migration, /grant execute on function public\.mme_person_authorize_inventory_action\(uuid,text,uuid,uuid\)\s+to service_role/);
  assert.match(migration, /from public, anon, authenticated/);
});

test("person authorization fails closed for missing identity, frozen access, missing CEO configuration and inactive employee relationship", () => {
  assert.equal((migration.match(/if p_actor_person_id is null/g) ?? []).length, 2);
  assert.equal((migration.match(/v_frozen is distinct from false or v_ceo_person_id is null/g) ?? []).length, 2);
  assert.equal((migration.match(/v_employment_status is distinct from 'active'/g) ?? []).length, 2);
  assert.equal((migration.match(/if not found or v_frozen/g) ?? []).length, 2);
});

test("catalog approval and publication resolve creator from protected product row and prohibit self-approval", () => {
  assert.match(migration, /mme_resolve_person_for_auth_subject\(created_by\)/);
  assert.match(migration, /p_actor_person_id = v_creator_person_id/);
  assert.match(migration, /v_catalog_status <> 'pending_approval'/);
  assert.match(migration, /v_approved_by is null or v_approved_at is null/);
});

test("permission grants are person-keyed, scoped, unexpired and not revoked", () => {
  assert.equal((migration.match(/g\.person_id = p_actor_person_id/g) ?? []).length, 2);
  assert.equal((migration.match(/g\.revoked_at is null/g) ?? []).length, 2);
  assert.equal((migration.match(/g\.expires_at is null or g\.expires_at > now\(\)/g) ?? []).length, 2);
  assert.match(migration, /g\.scope ->> 'product_id'/);
  assert.match(migration, /g\.scope ->> 'location_id'/);
});

test("person-keyed decision points do not silently fall back to legacy Auth authorization", () => {
  assert.match(migration, /do not fall back to Auth-UUID authorization/);
  assert.doesNotMatch(migration, /mme_employee_authorize_catalog_action\(/);
  assert.doesNotMatch(migration, /mme_employee_authorize_inventory_action\(/);
});
