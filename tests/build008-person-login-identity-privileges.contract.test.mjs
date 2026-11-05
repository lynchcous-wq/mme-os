import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  new URL("../supabase/migrations/20261103008420_build004_identity_privilege_hardening.sql", import.meta.url),
  "utf8",
);

test("identity tables are inaccessible to browser roles and explicitly available to trusted server role", () => {
  for (const table of ["mme_person_identities", "mme_login_identities"]) {
    assert.match(migration, new RegExp("revoke all on public\\." + table + "[\\s\\S]*?from public, anon, authenticated"));
    assert.match(migration, new RegExp("grant select, insert, update on public\\." + table + "[\\s\\S]*?to service_role"));
  }
});

test("timestamp helper is not exposed as an application RPC", () => {
  assert.match(migration, /revoke all on function public\.mme_person_identity_set_updated_at\(\)[\s\S]*?from public, anon, authenticated, service_role/);
});

test("identity resolver remains callable only by the trusted server role", () => {
  assert.match(migration, /revoke all on function public\.mme_resolve_person_for_auth_subject\(uuid\)[\s\S]*?from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.mme_resolve_person_for_auth_subject\(uuid\)[\s\S]*?to service_role/);
});
