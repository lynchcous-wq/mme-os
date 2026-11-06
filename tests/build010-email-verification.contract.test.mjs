import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/auth/verify-email/route.ts", import.meta.url), "utf8");
const page = await readFile(new URL("../app/account/verify-email/page.tsx", import.meta.url), "utf8");
const session = await readFile(new URL("../lib/auth/supabase-session.ts", import.meta.url), "utf8");
const registration = await readFile(new URL("../app/api/auth/register/route.ts", import.meta.url), "utf8");

test("verification endpoint is same-origin, JSON-only, bounded, and signup-email-only", () => {
  assert.match(route, /hasSameOrigin\(request\)/);
  assert.match(route, /application\/json/);
  assert.match(route, /input\.type !== "email"/);
  assert.match(route, /tokenHash\.length > 512/);
  assert.match(route, /\/auth\/v1\/verify/);
  assert.match(route, /token_hash: tokenHash, type: "email"/);
});

test("verification validates confirmed user and never issues session cookies", () => {
  assert.match(route, /getAuthUser\(verified\.access_token\)/);
  assert.match(route, /user\.email_confirmed_at/);
  assert.doesNotMatch(route, /setSessionCookies/);
  assert.match(route, /Tokens are intentionally discarded/);
});

test("verification page requires an explicit user click so email scanners do not consume links", () => {
  assert.match(page, /onClick=\{verify\}/);
  assert.match(page, /POST/);
  assert.match(page, /opening this page does not consume/);
  assert.match(page, /replaceState/);
});

test("auth user shape exposes email confirmation timestamp for verification checks", () => {
  assert.match(session, /email_confirmed_at\?: string \| null/);
});

test("registration continues to require email confirmation and never grants customer identity", () => {
  assert.match(registration, /result\.session/);
  assert.doesNotMatch(registration, /mme_customer_portal_provision_account_link/);
});
