import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  new URL("../supabase/migrations/20261103008440_build004_require_active_person_identity.sql", import.meta.url),
  "utf8",
);

test("catalog and inventory authorization reject missing and non-active person identities", () => {
  assert.equal((migration.match(/select lifecycle_status into v_person_status/g) ?? []).length, 2);
  assert.equal((migration.match(/if not found or v_person_status is distinct from 'active'/g) ?? []).length, 2);
});

test("employee relationship, CEO configuration and company freeze remain mandatory", () => {
  assert.equal((migration.match(/v_employment_status is distinct from 'active'/g) ?? []).length, 2);
  assert.equal((migration.match(/v_frozen is distinct from false or v_ceo_person_id is null/g) ?? []).length, 2);
});

test("person authorization functions remain server-only", () => {
  assert.match(migration, /revoke all on function public\.mme_person_authorize_catalog_action\(uuid,text,uuid\)[\s\S]*?from public, anon, authenticated/);
  assert.match(migration, /revoke all on function public\.mme_person_authorize_inventory_action\(uuid,text,uuid,uuid\)[\s\S]*?from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.mme_person_authorize_catalog_action\(uuid,text,uuid\)[\s\S]*?to service_role/);
  assert.match(migration, /grant execute on function public\.mme_person_authorize_inventory_action\(uuid,text,uuid,uuid\)[\s\S]*?to service_role/);
});

test("legacy authorization remains untouched and no person mappings are backfilled", () => {
  assert.doesNotMatch(migration, /mme_employee_authorize_catalog_action\(/);
  assert.doesNotMatch(migration, /mme_employee_authorize_inventory_action\(/);
  assert.doesNotMatch(migration, /insert into public\.mme_person_identities/i);
  assert.doesNotMatch(migration, /insert into public\.mme_login_identities/i);
  assert.doesNotMatch(migration, /update public\.employee_relationships/i);
});
