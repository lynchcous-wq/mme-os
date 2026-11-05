import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import ts from "typescript";
import { randomUUID } from "node:crypto";

const base = process.env.SUPABASE_URL;
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;

test("live Supabase Auth identity mapping and Build 004 deny decision", async (t) => {
  assert.ok(base && anon && service, "local Supabase URL, anon key and service-role key are required");

  const suffix = randomUUID();
  const email = `build004-live-${suffix}@example.invalid`;
  const password = `MmE-${randomUUID()}-Aa9!`;
  let userId;

  const adminHeaders = {
    apikey: service,
    Authorization: `Bearer ${service}`,
    "Content-Type": "application/json",
  };

  try {
    const created = await fetch(`${base}/auth/v1/admin/users`, {
      method: "POST",
      headers: adminHeaders,
      body: JSON.stringify({ email, password, email_confirm: true }),
    });
    const createdBody = await created.json();
    assert.equal(created.ok, true, "Supabase admin API creates isolated integration user");
    userId = createdBody.id;
    assert.match(userId, /^[0-9a-f-]{36}$/i);

    const signedIn = await fetch(`${base}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: anon, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    const session = await signedIn.json();
    assert.equal(signedIn.ok, true, "test user obtains a real Supabase Auth access token");
    assert.equal(session.user.id, userId);
    assert.ok(session.access_token);

    const identityQuery = new URLSearchParams({
      select: "id,auth_user_id",
      auth_user_id: `eq.${userId}`,
      limit: "2",
    });
    const identityResponse = await fetch(`${base}/rest/v1/mme_person_identities?${identityQuery}`, {
      headers: adminHeaders,
      cache: "no-store",
    });
    const identities = await identityResponse.json();
    assert.equal(identityResponse.ok, true, "service-role lookup reaches the real local database");
    assert.equal(identities.length, 1, "Auth trigger provisions exactly one separate person identity");
    assert.notEqual(identities[0].id, userId, "person identity UUID is distinct from Auth subject");

    const helperPath = new URL("../lib/server/identity-authorization.ts", import.meta.url);
    const source = readFileSync(helperPath, "utf8").replace(/^import ["']server-only["'];?\\s*/m, "");
    const compiled = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    }).outputText;
    const module = { exports: {} };
    vm.runInNewContext(compiled, {
      module,
      exports: module.exports,
      require: () => ({}),
      process: { env: {
        SUPABASE_URL: base,
        NEXT_PUBLIC_SUPABASE_ANON_KEY: anon,
        SUPABASE_SERVICE_ROLE_KEY: service,
      } },
      fetch,
    });
    const authorize = module.exports.authenticateAndAuthorizeEmployee;

    const denied = await authorize(
      session.access_token,
      "inventory.inspection",
      "submit",
      {
        product_id: "11111111-1111-4111-8111-111111111111",
        location_id: "22222222-2222-4222-8222-222222222222",
      },
    );
    assert.deepEqual(JSON.parse(JSON.stringify(denied)), {
      ok: false,
      status: 403,
      error: "Employee does not have the required permission.",
    }, "real Auth token reaches the real Build 004 RPC and receives a deny decision");

    const invalid = await authorize("not-a-valid-token", "inventory.inspection", "submit", {});
    assert.equal(invalid.ok, false);
    assert.equal(invalid.status, 401, "invalid bearer token is rejected by Supabase Auth");
  } finally {
    if (userId) {
      const removed = await fetch(`${base}/auth/v1/admin/users/${userId}`, {
        method: "DELETE",
        headers: adminHeaders,
      });
      assert.ok(removed.ok, "integration fixture user is removed after the test");
    }
  }
});
