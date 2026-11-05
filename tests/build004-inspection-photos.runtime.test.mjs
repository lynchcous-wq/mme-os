import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import ts from "typescript";
import { File } from "node:buffer";
import { createRequire } from "node:module";
const nodeRequire = createRequire(import.meta.url);

const source = readFileSync("app/api/employee/inventory/inspection/photos/route.ts", "utf8");
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
      if (name === "node:crypto") return nodeRequire("node:crypto");
      throw new Error("Unexpected import: " + name);
    },
    process: { env: ENV }, fetch: fetchImpl, URLSearchParams, Request, Response, FormData, File, Buffer,
    console,
  });
  return module.exports.POST;
}
function request({ bytes = Buffer.from([0xff,0xd8,0xff,0x00]), type = "image/jpeg", sizePadding = 0 } = {}) {
  const form = new FormData();
  form.set("inspection_id", INSPECTION_ID);
  form.set("caption", "Front condition evidence");
  form.set("file", new File([bytes, new Uint8Array(sizePadding)], "front.jpg", { type }));
  return new Request("https://mme-test.local/api/employee/inventory/inspection/photos", {
    method: "POST",
    headers: { authorization: "Bearer valid-token" },
    body: form,
  });
}
function fixture({
  disposition = "pending",
  owner = PERSON_ID,
  identityRows = [{ id: PERSON_ID }],
  metadataStatus = 200,
  authorizeImpl,
} = {}) {
  const calls = [];
  const fetchImpl = async (url, init = {}) => {
    const u = String(url);
    calls.push({ url: u, init });
    if (u.endsWith("/auth/v1/user")) return json({ id: AUTH_ID });
    if (u.includes("/mme_inventory_inspections?")) return json([{
      id: INSPECTION_ID, product_id: PRODUCT_ID, location_id: LOCATION_ID,
      inspected_by_identity_id: owner, disposition,
    }]);
    if (u.includes("/mme_person_identities?")) return json(identityRows);
    if (u.includes("/rpc/mme_employee_authorize_inventory_action")) return json(true);
    if (u.includes("/storage/v1/object/mme-inspection-evidence/") && init.method === "POST") return json({ Key: "stored" });
    if (u.endsWith("/rpc/mme_register_inspection_photo_evidence")) return json("77777777-7777-4777-8777-777777777777", metadataStatus);
    if (u.includes("/storage/v1/object/mme-inspection-evidence/") && init.method === "DELETE") return json({});
    throw new Error("Unexpected fetch: " + u);
  };
  return { handler: loadRoute(fetchImpl, authorizeImpl), calls };
}

test("photo route accepts valid private evidence and registers hash and mapped actor identity", async () => {
  const buildCalls = [];
  const { handler, calls } = fixture({
    authorizeImpl: async (_token, resource, action, scope) => {
      buildCalls.push({ resource, action, scope });
      return { ok: true, actorUserId: AUTH_ID };
    },
  });
  const response = await handler(request());
  const data = await response.json();
  assert.equal(response.status, 200);
  assert.equal(data.uploaded, true);
  assert.equal(buildCalls.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(buildCalls[0])), {
    resource: "inventory.inspection", action: "submit",
    scope: { product_id: PRODUCT_ID, location_id: LOCATION_ID },
  });
  const metadata = calls.find(x => x.url.endsWith("/rpc/mme_register_inspection_photo_evidence"));
  assert.ok(metadata);
  const payload = JSON.parse(metadata.init.body);
  assert.equal(payload.p_actor_identity_id, PERSON_ID);
  assert.match(payload.p_sha256_hex, /^[a-f0-9]{64}$/);
  assert.ok(calls.some(x => x.url.includes("/storage/v1/object/mme-inspection-evidence/") && x.init.method === "POST"));
});

test("photo route rejects a different uploader and a non-pending inspection before storage", async () => {
  for (const options of [{ owner: "88888888-8888-4888-8888-888888888888" }, { disposition: "resolved" }]) {
    const { handler, calls } = fixture(options);
    const response = await handler(request());
    assert.equal(response.status, 403);
    assert.equal(calls.some(x => x.url.includes("/storage/v1/object/")), false);
  }
});

test("photo route fails closed on Build 004 denial or authorization outage", async () => {
  for (const decision of [
    { ok: false, status: 403, error: "denied" },
    { ok: false, status: 503, error: "unavailable" },
  ]) {
    const { handler, calls } = fixture({ authorizeImpl: async () => decision });
    const response = await handler(request());
    assert.equal(response.status, decision.status);
    assert.equal(calls.some(x => x.url.includes("/storage/v1/object/")), false);
  }
});

test("photo route rejects mismatched file signatures before storage", async () => {
  const { handler, calls } = fixture();
  const response = await handler(request({ bytes: Buffer.from("not-a-jpeg"), type: "image/jpeg" }));
  assert.equal(response.status, 415);
  assert.equal(calls.some(x => x.url.includes("/storage/v1/object/")), false);
});

test("photo route rolls back private storage if evidence metadata registration fails", async () => {
  const { handler, calls } = fixture({ metadataStatus: 500 });
  const response = await handler(request());
  assert.equal(response.status, 409);
  assert.ok(calls.some(x => x.url.includes("/storage/v1/object/mme-inspection-evidence/") && x.init.method === "POST"));
  assert.ok(calls.some(x => x.url.includes("/storage/v1/object/mme-inspection-evidence/") && x.init.method === "DELETE"));
});

test("photo route rejects missing or ambiguous person identity mapping before upload", async () => {
  for (const identityRows of [[], [{ id: PERSON_ID }, { id: AUTH_ID }]]) {
    const { handler, calls } = fixture({ identityRows });
    const response = await handler(request());
    assert.equal(response.status, 403);
    assert.equal(calls.some(x => x.url.includes("/storage/v1/object/")), false);
  }
});
