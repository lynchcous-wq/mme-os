import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL("../" + path, import.meta.url), "utf8");
const [session, signIn, customer, employee, customerPage, employeePage, migration] = await Promise.all([
  read("lib/auth/supabase-session.ts"),
  read("app/api/auth/sign-in/route.ts"),
  read("app/api/auth/customer/route.ts"),
  read("app/api/auth/employee/route.ts"),
  read("app/account/page.tsx"),
  read("app/employee/sign-in/page.tsx"),
  read("supabase/migrations/20261106006100_build010_customer_security_session_center.sql"),
]);

test("shared authentication does not hard-code a customer-only or employee-only role", () => {
  assert.match(signIn, /passwordSignIn\(body\.email\.trim\(\),body\.password\)/);
  assert.match(signIn, /event_source:"mme_portal"/);
  assert.match(customerPage, /\/api\/auth\/sign-in/);
  assert.match(employeePage, /\/api\/auth\/sign-in/);
});

test("customer access requires an active account link and active identity", () => {
  assert.match(customer, /link_status=eq\.active/);
  assert.match(customer, /lifecycle_status=eq\.active/);
  assert.match(customer, /links\.length !== 1/);
  assert.match(customer, /identities\.length !== 1/);
});

test("employee access requires an active employee relationship", () => {
  assert.match(employee, /requireEmployeeIdentity\(session\.user\.id\)/);
  assert.match(session, /mme_resolve_person_for_auth_subject/);
  assert.match(session, /employment_status=eq\.active/);
});

test("browser sessions use HttpOnly, SameSite=Lax cookies and production Secure", () => {
  assert.match(session, /httpOnly:\s*true/);
  assert.match(session, /sameSite:\s*"lax"/);
  assert.match(session, /secure, path:\s*"\/", maxAge/);
  assert.match(session, /process\.env\.NODE_ENV === "production"/);
});

test("security event history is owner-scoped, append-only, and not browser-writable", () => {
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /auth_user_id=auth\.uid\(\)/);
  assert.match(migration, /revoke all .* from public,anon,authenticated/i);
  assert.match(migration, /before update or delete/i);
});
