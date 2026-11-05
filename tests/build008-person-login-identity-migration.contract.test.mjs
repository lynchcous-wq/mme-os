import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  new URL("../supabase/migrations/20261103008400_build004_person_login_identity_bridge.sql", import.meta.url),
  "utf8",
);

test("identity bridge creates stable person and provider login entities", () => {
  assert.match(migration, /create table public\.mme_person_identities/);
  assert.match(migration, /person_id uuid primary key/);
  assert.match(migration, /create table public\.mme_login_identities/);
  assert.match(migration, /unique \(provider_key, provider_subject\)/);
  assert.match(migration, /create unique index mme_login_identities_auth_user_uidx/);
  assert.match(migration, /provider_key = 'supabase'/);
});

test("legacy employee and grant identities remain intact during nullable additive phase", () => {
  assert.match(migration, /alter table public\.employee_relationships\s+add column person_id uuid references/);
  assert.match(migration, /alter table public\.employee_permission_grants\s+add column person_id uuid references/);
  assert.match(migration, /granted_by_person_id uuid references/);
  assert.match(migration, /revoked_by_person_id uuid references/);
  assert.match(migration, /add column ceo_person_id uuid references/);
  assert.match(migration, /add column actor_person_id uuid references/);
  assert.match(migration, /add column target_employee_person_id uuid references/);
  assert.doesNotMatch(migration, /update public\.(employee_relationships|employee_permission_grants|employee_security_settings|employee_access_audit_events)\s+set/i);
  assert.doesNotMatch(migration, /drop column|drop table|delete from public\.(employee_relationships|employee_permission_grants)/i);
});

test("person and login mappings are private and resolver fails closed", () => {
  assert.match(migration, /alter table public\.mme_person_identities enable row level security/);
  assert.match(migration, /alter table public\.mme_person_identities force row level security/);
  assert.match(migration, /alter table public\.mme_login_identities enable row level security/);
  assert.match(migration, /revoke all on public\.mme_person_identities from public, anon, authenticated/);
  assert.match(migration, /revoke all on public\.mme_login_identities from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.mme_resolve_person_for_auth_subject\(uuid\)\s+to service_role/);
  assert.match(migration, /l\.link_status = 'verified'/);
  assert.match(migration, /l\.revoked_at is null/);
  assert.match(migration, /p\.lifecycle_status = 'active'/);
  assert.match(migration, /if p_auth_user_id is null then\s+return null/);
});
