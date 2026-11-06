import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const route = await readFile(new URL("../app/api/warranty/compliance/route.ts", import.meta.url), "utf8");

test("requires bearer session and verifies it with Supabase Auth", () => {
  assert.match(route, /authorization\.match\(\/\^Bearer/);
  assert.match(route, /\/auth\/v1\/user/);
  assert.match(route, /invalid_session/);
});
test("uses a fixed resource allowlist rather than accepting table names", () => {
  for (const name of ["summary","calendar","approvals","alerts","assignments"]) assert.ok(route.includes(name));
  assert.match(route, /VIEW_BY_RESOURCE/);
  assert.doesNotMatch(route, /searchParams\.get\(["']view|searchParams\.get\(["']table/);
});
test("enforces server-verified application roles per resource", () => {
  assert.match(route, /user\.app_metadata/);
  assert.match(route, /ROLE_ACCESS\[resource\]/);
  assert.match(route, /insufficient_permissions/);
});
test("does not expose service credentials to the client and disables caching", () => {
  assert.match(route, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(route, /Authorization: "Bearer " \+ serviceKey/);
  assert.match(route, /Cache-Control.*no-store/);
});
test("bounds response size and rejects malformed database responses", () => {
  assert.match(route, /data\.slice\(0, 500\)/);
  assert.match(route, /invalid_compliance_response/);
});
test("returns generic errors without forwarding provider response bodies", () => {
  assert.match(route, /compliance_data_query_failed/);
  assert.doesNotMatch(route, /response\.text\(\)|response\.json\(\).*error/);
});
