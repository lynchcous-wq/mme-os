import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import ts from "typescript";

const source = readFileSync("lib/server/identity-authorization.ts", "utf8")
  .replace(/^import ["']server-only["'];?\s*/m, "");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;

const AUTH_ID = "11111111-1111-4111-8111-111111111111";
const PERSON_ID = "22222222-2222-4222-8222-222222222222";
const env = {
  SUPABASE_URL: "https://mme-test.supabase.co",
  NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon",
  SUPABASE_SERVICE_ROLE_KEY: "test-service",
};

function loadHelper(fetchImpl, overrides = {}) {
  const module = { exports: {} };
  const context = {
    module,
    exports: module.exports,
    require: () => ({}),
    process: { env: { ...env, ...overrides } },
    fetch: fetchImpl,
  };
  vm.runInNewContext(compiled, context, { filename: "identity-authorization.ts" });
  return module.exports.authenticateAndAuthorizeEmployee;
}

function response(ok, body) {
  return { ok, json: async () => body };
}

const scope = { product_id: "33333333-3333-4333-8333-333333333333", location_id: "44444444-4444-4444-8444-444444444444" };

test("runtime helper allows only after Auth validation and true Build 004 RPC decision", async () => {
  const calls = [];
  const authorize = loadHelper(async (url, init) => {
    calls.push({ url, init });
    return calls.length === 1 ? response(true, { id: AUTH_ID }) : response(true, true);
  });
  const result = await authorize("valid-token", "inventory.inspection", "submit", scope);
  assert.equal(result.ok, true);
  assert.equal(result.actorUserId, AUTH_ID);
  assert.equal(calls.length, 2);
  assert.match(calls[0].url, /\/auth\/v1\/user$/);
  assert.match(calls[1].url, /mme_authorize_employee_action$/);
  const payload = JSON.parse(calls[1].init.body);
  assert.equal(payload.p_actor_auth_user_id, AUTH_ID);
  assert.equal(payload.p_resource_key, "inventory.inspection");
  assert.equal(payload.p_action_key, "submit");
  assert.deepEqual(JSON.parse(JSON.stringify(payload.p_requested_scope)), scope);
  assert.equal(calls[1].init.headers.Authorization, "Bearer test-service");
});

test("runtime helper denies an inactive, frozen, terminated or ungranted actor when RPC returns false", async () => {
  let count = 0;
  const authorize = loadHelper(async () => ++count === 1 ? response(true, { id: AUTH_ID }) : response(true, false));
  const result = await authorize("valid-token", "inventory.inspection", "view", scope);
  assert.equal(result.ok, false);
  assert.equal(result.status, 403);
});

test("runtime helper rejects invalid Auth sessions before calling authorization RPC", async () => {
  let calls = 0;
  const authorize = loadHelper(async () => { calls++; return response(false, {}); });
  const result = await authorize("expired-token", "inventory.inspection", "submit", scope);
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
  assert.equal(calls, 1);
});

test("runtime helper fails closed with 503 when authorization RPC is unavailable", async () => {
  let calls = 0;
  const authorize = loadHelper(async () => ++calls === 1
    ? response(true, { id: AUTH_ID })
    : response(false, { message: "database unavailable" }));
  const result = await authorize("valid-token", "inventory.inspection", "resolve", scope);
  assert.equal(result.ok, false);
  assert.equal(result.status, 503);
});

test("runtime helper rejects malformed Auth identity and does not call authorization RPC", async () => {
  let calls = 0;
  const authorize = loadHelper(async () => { calls++; return response(true, { id: "not-a-uuid" }); });
  const result = await authorize("valid-token", "inventory.inspection", "submit", scope);
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
  assert.equal(calls, 1);
});

test("runtime helper returns the Auth subject, not a caller-supplied person identity", async () => {
  const calls = [];
  const authorize = loadHelper(async (url, init) => {
    calls.push({ url, init });
    return calls.length === 1 ? response(true, { id: AUTH_ID }) : response(true, true);
  });
  const result = await authorize("valid-token", "inventory.inspection", "approve", {
    ...scope,
    actor_identity_id: PERSON_ID,
  });
  assert.equal(result.ok, true);
  assert.equal(result.actorUserId, AUTH_ID);
  const payload = JSON.parse(calls[1].init.body);
  assert.equal(payload.p_actor_auth_user_id, AUTH_ID);
  assert.equal(payload.p_requested_scope.actor_identity_id, PERSON_ID);
});
