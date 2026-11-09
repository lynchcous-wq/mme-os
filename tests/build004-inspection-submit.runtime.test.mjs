import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import ts from "typescript";

const source = readFileSync("app/api/employee/inventory/inspection/route.ts", "utf8");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;
const AUTH_ID = "11111111-1111-4111-8111-111111111111";
const PERSON_ID = "22222222-2222-4222-8222-222222222222";
const UNIT_ID = "33333333-3333-4333-8333-333333333333";
const PRODUCT_ID = "44444444-4444-4444-8444-444444444444";
const LOCATION_ID = "55555555-5555-4555-8555-555555555555";
const ENV = {
  SUPABASE_URL: "https://mme-test.supabase.co",
  NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon",
  SUPABASE_SERVICE_ROLE_KEY: "test-service",
};
function json(body, init = {}) {
  const status = typeof init === "number" ? init : (init?.status ?? 200);
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
function loadRoute(fetchImpl, authorizeImpl = async () => ({ ok: true, actorUserId: AUTH_ID })) {
  const module = { exports: {} };
  vm.runInNewContext(compiled, {
    module, exports: module.exports,
    require(name) {
      if (name === "next/server") return { NextResponse: { json } };
      if (name === "@/lib/server/identity-authorization") return { authenticateAndAuthorizeEmployee: authorizeImpl };
      throw new Error("Unexpected import: " + name);
    },
    process: { env: ENV }, fetch: fetchImpl, URLSearchParams, Request, Response,
  });
  return module.exports.POST;
}
function body() {
  return {
    reference: "MME-SERIAL-001",
    inspection_type: "quality_check",
    reason: "Quality verification before resale",
    findings: { cosmetic: "clean" },
    battery_health_percent: 95,
    battery_test: "pass",
    screen_test: "pass",
    camera_test: "pass",
    charging_port_test: "pass",
    buttons_audio_test: "pass",
    connectivity_test: "pass",
    imei_serial_verification: "pass",
    activation_lock_status: "clear",
    notes: "All required checks completed",
  };
}
function request() {
  return new Request("https://mme-test.local/api/employee/inventory/inspection", {
    method: "POST",
    headers: { authorization: "Bearer valid-token", "content-type": "application/json" },
    body: JSON.stringify(body()),
  });
}
function fixture({ identityRows = [{ id: PERSON_ID }], rpcStatus = 200 } = {}) {
  const calls = [];
  const fetchImpl = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("mme_serialized_units?")) return json([{
      id: UNIT_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID,
    }]);
    if (u.includes("mme_person_identities?")) return json(identityRows);
    if (u.endsWith("/rpc/mme_submit_serialized_inspection")) return json("66666666-6666-4666-8666-666666666666", rpcStatus);
    throw new Error("Unexpected fetch: " + u);
  };
  return { handler: loadRoute(fetchImpl), calls };
}

test("submit route authorizes using database-derived unit scope and sends mapped person identity to atomic RPC", async () => {
  const authCalls = [];
  const fetchCalls = [];
  const fetchImpl = async (url, init = {}) => {
    fetchCalls.push({ url: String(url), init });
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("mme_serialized_units?")) return json([{ id: UNIT_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID }]);
    if (u.includes("mme_person_identities?")) return json([{ id: PERSON_ID }]);
    if (u.endsWith("/rpc/mme_submit_serialized_inspection")) return json("77777777-7777-4777-8777-777777777777");
    throw new Error("Unexpected fetch: " + u);
  };
  const handler = loadRoute(fetchImpl, async (_token, resource, action, scope) => {
    authCalls.push({ resource, action, scope });
    return { ok: true, actorUserId: AUTH_ID };
  });
  const response = await handler(request());
  const result = await response.json();
  assert.equal(response.status, 200);
  assert.equal(result.status, "quarantined_pending_review");
  assert.deepEqual(JSON.parse(JSON.stringify(authCalls)), [{
    resource: "inventory.inspection", action: "submit",
    scope: { product_id: PRODUCT_ID, location_id: LOCATION_ID },
  }]);
  const rpc = fetchCalls.find(x => x.url.endsWith("/rpc/mme_submit_serialized_inspection"));
  assert.ok(rpc);
  const payload = JSON.parse(rpc.init.body);
  assert.equal(payload.p_actor_user_id, AUTH_ID);
  assert.equal(payload.p_actor_identity_id, PERSON_ID);
  assert.notEqual(payload.p_actor_identity_id, AUTH_ID);
});

test("submit route stops before atomic RPC when Build 004 denies access", async () => {
  let rpcCalled = false;
  const fetchImpl = async (url) => {
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("mme_serialized_units?")) return json([{ id: UNIT_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID }]);
    if (u.includes("mme_person_identities?")) return json([{ id: PERSON_ID }]);
    if (u.endsWith("/rpc/mme_submit_serialized_inspection")) rpcCalled = true;
    throw new Error("Unexpected fetch: " + u);
  };
  const handler = loadRoute(fetchImpl, async () => ({ ok: false, status: 403, error: "denied" }));
  const response = await handler(request());
  assert.equal(response.status, 403);
  assert.equal(rpcCalled, false);
});

test("submit route rejects missing or duplicate person identity mapping", async () => {
  for (const rows of [[], [{ id: PERSON_ID }, { id: AUTH_ID }]]) {
    const fetchImpl = async (url) => {
      const u = String(url);
      if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
      if (u.includes("mme_serialized_units?")) return json([{ id: UNIT_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID }]);
      if (u.includes("mme_person_identities?")) return json(rows);
      throw new Error("Must stop before write: " + u);
    };
    const response = await loadRoute(fetchImpl)(request());
    assert.equal(response.status, 403);
  }
});

test("submit route propagates Build 004 authorization service outage as 503", async () => {
  const fetchImpl = async (url) => {
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("mme_serialized_units?")) return json([{ id: UNIT_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID }]);
    if (u.includes("mme_person_identities?")) return json([{ id: PERSON_ID }]);
    throw new Error("Must stop before write: " + u);
  };
  const handler = loadRoute(fetchImpl, async () => ({ ok: false, status: 503, error: "service unavailable" }));
  const response = await handler(request());
  assert.equal(response.status, 503);
});

test("submit route reports identity service outage as 503 instead of a permission denial", async () => {
  const fetchImpl = async (url) => {
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("mme_serialized_units?")) return json([{ id: UNIT_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID }]);
    if (u.includes("mme_person_identities?")) return json({ message: "database unavailable" }, 503);
    throw new Error("Must stop before authorization and write: " + u);
  };
  const handler = loadRoute(fetchImpl);
  const response = await handler(request());
  assert.equal(response.status, 503);
});

test("submit route rejects an authorization result bound to a different Auth session", async () => {
  let writeAttempted = false;
  const fetchImpl = async (url) => {
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("mme_serialized_units?")) return json([{ id: UNIT_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID }]);
    if (u.includes("mme_person_identities?")) return json([{ id: PERSON_ID }]);
    if (u.endsWith("/rpc/mme_submit_serialized_inspection")) writeAttempted = true;
    throw new Error("Unexpected fetch: " + u);
  };
  const handler = loadRoute(fetchImpl, async () => ({ ok: true, actorUserId: "99999999-9999-4999-8999-999999999999" }));
  const response = await handler(request());
  assert.equal(response.status, 401);
  assert.equal(writeAttempted, false);
});
