import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/auth/register/route.ts", import.meta.url), "utf8");
const page = await readFile(new URL("../app/account/register/page.tsx", import.meta.url), "utf8");
const customerAccess = await readFile(new URL("../app/api/auth/customer/route.ts", import.meta.url), "utf8");

test("registration is same-origin, JSON-only, bounded, and uses Supabase Auth signup", () => {
  assert.match(route, /hasSameOrigin\(request\)/);
  assert.match(route, /application\/json/);
  assert.match(route, /length < 12/);
  assert.match(route, /length > 128/);
  assert.match(route, /\/auth\/v1\/signup/);
  assert.match(route, /cache: "no-store"/);
});

test("registration never creates a browser session or grants customer or employee roles", () => {
  assert.doesNotMatch(route, /setSessionCookies/);
  assert.doesNotMatch(route, /mme_customer_portal_provision_account_link/);
  assert.doesNotMatch(route, /employee_relationships/);
  assert.match(route, /if \(result\.session\)/);
  assert.match(route, /email confirmation is enabled/);
});

test("registration UI requires matching password confirmation and links to existing sign-in", () => {
  assert.match(page, /password !== confirmation/);
  assert.match(page, /minLength=\{12\}/);
  assert.match(page, /href="\/account"/);
});

test("customer authorization continues to require a separately provisioned active identity link", () => {
  assert.match(customerAccess, /mme_customer_account_links/);
  assert.match(customerAccess, /link_status=eq\.active/);
  assert.match(customerAccess, /mme_person_identities/);
});
