import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import ts from "typescript";

const source = readFileSync("app/api/employee/inventory/inspection/history/route.ts", "utf8");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;
const AUTH_ID = "11111111-1111-4111-8111-111111111111";
const PERSON_ID = "22222222-2222-4222-8222-222222222222";
const INSPECTION_ID = "33333333-3333-4333-8333-333333333333";
const PRODUCT_ID = "44444444-4444-4444-8444-444444444444";
const LOCATION_ID = "55555555-5555-4555-8555-555555555555";
const ENV = {
  SUPABASE_URL: "https://mme-test.supabase.co",
  NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon",
  SUPABASE_SERVICE_ROLE_KEY: "test-service",
};
function json(body, status = 200) {
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
  return module.exports.GET;
}
function request() {
  return new Request("https://mme-test.local/api/employee/inventory/inspection/history", {
    headers: { authorization: "Bearer valid-token" },
  });
}
function fixture({ legacyStatus = 200, rows = [{ id: INSPECTION_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID }] } = {}) {
  const calls = [];
  const fetchImpl = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("/mme_person_identities?")) return json([{ id: PERSON_ID }]);
    if (u.includes("/mme_inventory_inspections?")) return json(rows);
    if (u.endsWith("/rpc/mme_employee_authorize_inventory_action")) return json(true, legacyStatus);
    if (u.includes("/mme_serialized_unit_dispositions?")) return json([]);
    throw new Error("Unexpected fetch: " + u);
  };
  return { handler: loadRoute(fetchImpl), calls };
}

test("history returns only own inspections after Build 004 and legacy view authorization", async () => {
  const buildCalls = [];
  const { handler, calls } = fixture();
  const fetchImpl = async (url, init = {}) => {
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("/mme_person_identities?")) return json([{ id: PERSON_ID }]);
    if (u.includes("/mme_inventory_inspections?")) return json([{ id: INSPECTION_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID }]);
    if (u.endsWith("/rpc/mme_employee_authorize_inventory_action")) return json(true);
    if (u.includes("/mme_serialized_unit_dispositions?")) return json([]);
    throw new Error("Unexpected fetch: " + u);
  };
  const handlerWithAuth = loadRoute(fetchImpl, async (_token, resource, action, scope) => {
    buildCalls.push({ resource, action, scope });
    return { ok: true, actorUserId: AUTH_ID };
  });
  const response = await handlerWithAuth(request());
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.inspections.length, 1);
  assert.deepEqual(buildCalls, [{
    resource: "inventory.inspection", action: "view",
    scope: { product_id: PRODUCT_ID, location_id: LOCATION_ID },
  }]);
  assert.ok(data.dispositions);
  const identityQuery = calls.find(x => x.url.includes("/mme_person_identities?"));
  assert.ok(identityQuery);
  assert.ok(identityQuery.url.includes(encodeURIComponent(AUTH_ID)) || identityQuery.url.includes(AUTH_ID));
  void handler;
});

test("history filters records denied by Build 004 without exposing them", async () => {
  const rows = [
    { id: INSPECTION_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID },
    { id: "66666666-6666-4666-8666-666666666666", product_id: PRODUCT_ID, location_id: LOCATION_ID },
  ];
  let count = 0;
  const fetchImpl = async (url) => {
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("/mme_person_identities?")) return json([{ id: PERSON_ID }]);
    if (u.includes("/mme_inventory_inspections?")) return json(rows);
    if (u.endsWith("/rpc/mme_employee_authorize_inventory_action")) return json(true);
    if (u.includes("/mme_serialized_unit_dispositions?")) return json([]);
    throw new Error("Unexpected fetch: " + u);
  };
  const handler = loadRoute(fetchImpl, async () => {
    count++;
    return count === 1
      ? { ok: true, actorUserId: AUTH_ID }
      : { ok: false, status: 403, error: "denied" };
  });
  const response = await handler(request());
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.deepEqual(data.inspections.map(x => x.id), [INSPECTION_ID]);
});

test("history fails closed with 503 when Build 004 authorization service is unavailable", async () => {
  const { handler } = fixture();
  const fetchImpl = async (url) => {
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("/mme_person_identities?")) return json([{ id: PERSON_ID }]);
    if (u.includes("/mme_inventory_inspections?")) return json([{ id: INSPECTION_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID }]);
    throw new Error("Must stop before legacy query: " + u);
  };
  const outage = loadRoute(fetchImpl, async () => ({ ok: false, status: 503, error: "unavailable" }));
  const response = await outage(request());
  assert.equal(response.status, 503);
  void handler;
});

test("history fails closed when legacy authorization RPC is unavailable", async () => {
  const { handler } = fixture({ legacyStatus: 503 });
  const response = await handler(request());
  assert.equal(response.status, 503);
});

test("history rejects missing or ambiguous person identity mapping", async () => {
  for (const identities of [[], [{ id: PERSON_ID }, { id: AUTH_ID }]]) {
    const fetchImpl = async (url) => {
      const u = String(url);
      if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
      if (u.includes("/mme_person_identities?")) return json(identities);
      throw new Error("Must stop before history query: " + u);
    };
    const response = await loadRoute(fetchImpl)(request());
    assert.equal(response.status, 403);
  }
});
