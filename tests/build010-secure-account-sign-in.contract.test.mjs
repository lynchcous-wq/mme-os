import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("browser session tokens are HttpOnly and never returned as JSON", () => {
  const source = read("../lib/auth/supabase-session.ts");
  assert.match(source, /httpOnly:\s*true/);
  assert.match(source, /sameSite:\s*"lax"/);
  assert.match(source, /secure,/);
  assert.match(source, /mme_access_token/);
  assert.match(source, /mme_refresh_token/);
});

test("sign-in enforces same-origin JSON and bounded credentials", () => {
  const source = read("../app/api/auth/sign-in/route.ts");
  assert.match(source, /hasSameOrigin\(request\)/);
  assert.match(source, /application\/json/);
  assert.match(source, /body\.email\.length > 320/);
  assert.match(source, /body\.password\.length > 1024/);
  assert.doesNotMatch(source, /access_token\s*:/);
});

test("employee authorization requires verified person identity and active employment", () => {
  const source = read("../lib/auth/supabase-session.ts");
  assert.match(source, /mme_resolve_person_for_auth_subject/);
  assert.match(source, /employee_relationships\?person_id=eq\./);
  assert.match(source, /employment_status=eq\.active/);
});

test("customer and employee relationship checks are separate", () => {
  const customer = read("../app/api/auth/customer/route.ts");
  const employee = read("../app/api/auth/employee/route.ts");
  assert.match(customer, /mme_customer_account_links/);
  assert.match(customer, /mme_person_identities/);
  assert.match(employee, /requireEmployeeIdentity/);
  assert.doesNotMatch(customer, /employee_relationships/);
});

test("session refresh rotates both HttpOnly cookies and sign-out clears them", () => {
  const session = read("../app/api/auth/session/route.ts");
  const signOut = read("../app/api/auth/sign-out/route.ts");
  assert.match(session, /setSessionCookies/);
  assert.match(signOut, /clearSessionCookies/);
});
