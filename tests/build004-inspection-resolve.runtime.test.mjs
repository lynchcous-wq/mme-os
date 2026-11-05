import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import ts from "typescript";

const source = readFileSync("app/api/employee/inventory/inspection/resolve/route.ts", "utf8");
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

function loadRoute({ fetchImpl, authorizeImpl = async () => ({ ok: true, actorUserId: AUTH_ID }), env = {} }) {
  const module = { exports: {} };
  const context = {
    module, exports: module.exports,
    require(name) {
      if (name === "next/server") return { NextResponse: { json } };
      if (name === "@/lib/server/identity-authorization") return { authenticateAndAuthorizeEmployee: authorizeImpl };
      throw new Error("Unexpected import: " + name);
    },
    process: { env: { ...ENV, ...env } },
    fetch: fetchImpl,
    URLSearchParams,
    Request,
    Response,
    console,
  };
  vm.runInNewContext(compiled, context, { filename: "inspection-resolve-route.ts" });
  return module.exports.POST;
}

function setup({ authorizeImpl, legacyStatus = 200, resolutionResult = true } = {}) {
  const calls = [];
  const fetchImpl = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    const u = String(url);
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("/mme_inventory_inspections?")) return json([{
      id: INSPECTION_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID,
      serialized_unit_id: "66666666-6666-4666-8666-666666666666", disposition: "pending",
    }]);
    if (u.includes("/mme_person_identities?")) return json([{ id: PERSON_ID }]);
    if (u.endsWith("/rpc/mme_employee_authorize_inventory_action")) {
      return json(true, legacyStatus);
    }
    if (u.endsWith("/rpc/mme_resolve_serialized_inspection")) return json(resolutionResult);
    throw new Error("Unexpected fetch: " + u);
  };
  return { handler: loadRoute({ fetchImpl, authorizeImpl }), calls };
}

function request() {
  return new Request("https://mme-test.local/api/employee/inventory/inspection/resolve", {
    method: "POST",
    headers: { authorization: "Bearer valid-token", "content-type": "application/json" },
    body: JSON.stringify({
      inspection_id: INSPECTION_ID,
      resolution: "return_to_stock",
      condition_after: "used",
      reason: "Inspected and confirmed saleable",
    }),
  });
}

test("resolve route allows only after both Build 004 actions and legacy checks pass", async () => {
  const actions = [];
  const { handler, calls } = setup({
    authorizeImpl: async (_token, _resource, action, scope) => {
      actions.push({ action, scope });
      return { ok: true, actorUserId: AUTH_ID };
    },
  });
  const response = await handler(request());
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.status, "resolved");
  assert.deepEqual(actions.map(x => x.action), ["approve", "resolve"]);
  assert.deepEqual(actions[0].scope, { product_id: PRODUCT_ID, location_id: LOCATION_ID });
  assert.equal(calls.filter(x => x.url.includes("/rpc/mme_employee_authorize_inventory_action")).length, 2);
  const finalCall = calls.find(x => x.url.endsWith("/rpc/mme_resolve_serialized_inspection"));
  assert.ok(finalCall);
  const payload = JSON.parse(finalCall.init.body);
  assert.equal(payload.p_actor_identity_id, PERSON_ID);
  assert.equal(payload.p_approved_by_identity_id, PERSON_ID);
  assert.notEqual(payload.p_actor_identity_id, AUTH_ID);
});

test("resolve route stops before legacy checks when Build 004 denies approval", async () => {
  let actions = 0;
  const { handler, calls } = setup({
    authorizeImpl: async () => { actions++; return { ok: false, status: 403, error: "denied" }; },
  });
  const response = await handler(request());
  assert.equal(response.status, 403);
  assert.equal(actions, 1);
  assert.equal(calls.some(x => x.url.includes("/rpc/mme_employee_authorize_inventory_action")), false);
  assert.equal(calls.some(x => x.url.includes("/rpc/mme_resolve_serialized_inspection")), false);
});

test("resolve route fails closed when the legacy permission service is unavailable", async () => {
  const { handler } = setup({ legacyStatus: 503 });
  const response = await handler(request());
  assert.equal(response.status, 503);
});

test("resolve route refuses a non-pending inspection before authorizing or resolving", async () => {
  const { handler } = setup();
  const fetchOriginal = globalThis.fetch;
  // The fixture is modified in the dedicated fetch below to represent a closed inspection.
  const module = { exports: {} };
  const closedHandler = loadRoute({
    fetchImpl: async (url) => {
      const u = String(url);
      if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
      if (u.includes("/mme_inventory_inspections?")) return json([{
        id: INSPECTION_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID,
        serialized_unit_id: null, disposition: "resolved",
      }]);
      throw new Error("Closed inspections must stop before additional lookups: " + u);
    },
  });
  const response = await closedHandler(request());
  assert.equal(response.status, 409);
  void handler; void fetchOriginal; void module;
});
