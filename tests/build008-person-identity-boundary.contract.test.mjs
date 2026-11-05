import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL("../" + path, import.meta.url), "utf8");

test("Build 004 contract separates stable person identity from provider login subject", async () => {
  const contract = await read("docs/BUILD-004-PERSON-IDENTITY-INTEGRATION-CONTRACT.md");
  assert.match(contract, /stable MME `person_id`/);
  assert.match(contract, /Provider subject/);
  assert.match(contract, /email is an attribute to verify/);
  assert.match(contract, /Employee relationship.*Customer relationship/s);
  assert.match(contract, /A provider subject maps to at most one person/);
});

test("legacy employee schema is explicitly recognized as a compatibility gap", async () => {
  const legacy = await read("supabase/migrations/20261103000002_catalog_integration_employee_access_control.sql");
  const authz = await read("supabase/migrations/20261103000003_catalog_integration_employee_authorization_engine.sql");
  const inventoryAuthz = await read("supabase/migrations/20261103007900_build001_inspection_employee_permissions.sql");
  const contract = await read("docs/BUILD-004-PERSON-IDENTITY-INTEGRATION-CONTRACT.md");
  assert.match(legacy, /user_id uuid primary key references auth\.users\(id\)/);
  assert.match(legacy, /employee_user_id uuid not null references public\.employee_relationships\(user_id\)/);
  assert.match(authz, /p_actor_user_id uuid/);
  assert.match(inventoryAuthz, /p_actor_user_id uuid/);
  assert.match(contract, /not yet implemented/);
  assert.match(contract, /Do not merge or deploy the employee authorization migrations/);
});

test("person identity contract requires fail-closed linking and relationship separation", async () => {
  const contract = await read("docs/BUILD-004-PERSON-IDENTITY-INTEGRATION-CONTRACT.md");
  for (const invariant of [
    "Unmapped, duplicate, conflicting, disabled or unverified subjects fail closed",
    "Terminating or suspending the employee relationship must not change the customer relationship",
    "No employee may create, claim, or link another person's identity",
    "No RPC accepts an arbitrary actor identity from an untrusted browser",
    "Customer freeze changes only customer state",
  ]) {
    assert.ok(contract.includes(invariant), "Missing identity invariant: " + invariant);
  }
});
