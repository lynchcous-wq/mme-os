import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261106004000_build010_customer_identity_link_requests.sql", import.meta.url), "utf8");
const route = await readFile(new URL("../app/api/auth/customer/link-request/route.ts", import.meta.url), "utf8");
const page = await readFile(new URL("../app/account/link-request/page.tsx", import.meta.url), "utf8");
const customerAccess = await readFile(new URL("../app/api/auth/customer/route.ts", import.meta.url), "utf8");

test("link requests are separate from customer identity links and service-role only", () => {
  assert.match(migration, /create table public\.mme_customer_identity_link_requests/);
  assert.match(migration, /create table public\.mme_customer_identity_link_request_audit/);
  assert.match(migration, /enable row level security/);
  assert.match(migration, /revoke all .* from public,anon,authenticated/);
  assert.match(migration, /does not grant account access/);
  assert.match(migration, /unique index mme_customer_identity_link_one_pending_uidx/);
});

test("request API requires authenticated user with verified email and server-side service credentials", () => {
  assert.match(route, /requireBrowserUser/);
  assert.match(route, /user\.email_confirmed_at/);
  assert.match(route, /hasSameOrigin\(request\)/);
  assert.match(route, /content-length/);
  assert.match(route, /byteLength\(\) > 4096/);
  assert.match(route, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(route, /mme_customer_identity_link_requests/);
  assert.doesNotMatch(route, /mme_customer_portal_provision_account_link/);
});

test("request UI collects only optional matching references and avoids sensitive credentials", () => {
  assert.match(page, /customerReference/);
  assert.match(page, /phoneLast4/);
  assert.match(page, /Do not submit passwords/);
});

test("customer authorization remains gated on an active pre-existing account link and active identity", () => {
  assert.match(customerAccess, /mme_customer_account_links/);
  assert.match(customerAccess, /link_status=eq\.active/);
  assert.match(customerAccess, /mme_person_identities/);
  assert.match(customerAccess, /lifecycle_status=eq\.active/);
});
