import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync("lib/server/identity-authorization.ts", "utf8");

test("identity authorization helper is explicitly server-only", () => {
  assert.match(source, /^import ["']server-only["'];/);
});

test("actor identity is derived from Supabase Auth response", () => {
  assert.match(source, /\/auth\/v1\/user/);
  assert.match(source, /const user = await auth\.json\(\)/);
  assert.match(source, /p_actor_auth_user_id:\s*user\.id/);
  assert.doesNotMatch(source, /request\.json|searchParams|get\(["']actor/i);
});

test("authorization uses service-only RPC and explicit resource/action/scope", () => {
  assert.match(source, /mme_authorize_employee_action/);
  assert.match(source, /apikey:\s*service/);
  assert.match(source, /Authorization:\s*`Bearer \$\{service\}`/);
  assert.match(source, /p_resource_key:\s*resourceKey/);
  assert.match(source, /p_action_key:\s*actionKey/);
  assert.match(source, /p_requested_scope:\s*requestedScope/);
});

test("authorization fails closed on Auth, RPC, and denial outcomes", () => {
  assert.match(source, /status:\s*401/);
  assert.match(source, /status:\s*503/);
  assert.match(source, /status:\s*403/);
  assert.match(source, /await decision\.json\(\) !== true/);
  assert.match(source, /cache:\s*["']no-store["']/);
});

test("actor IDs must be UUIDs and scopes are caller-supplied trusted server data", () => {
  assert.match(source, /UUID\.test\(user\.id\)/);
  assert.match(source, /requestedScope:\s*IdentityScope/);
});
