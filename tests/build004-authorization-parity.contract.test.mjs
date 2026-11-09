import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const helper = readFileSync("lib/server/identity-authorization.ts", "utf8");
const routes = [
  "app/api/employee/inventory/inspection/route.ts",
  "app/api/employee/inventory/inspection/history/route.ts",
  "app/api/employee/inventory/inspection/photos/route.ts",
  "app/api/employee/inventory/inspection/resolve/route.ts",
];

test("shared authorization helper validates the bearer with Supabase Auth", () => {
  assert.match(helper, /\/auth\/v1\/user/);
  assert.match(helper, /if \(!auth\.ok\) return \{ ok: false, status: 401/);
});

test("shared authorization helper derives actor identity from validated Auth response", () => {
  assert.match(helper, /const user = await auth\.json\(\)/);
  assert.match(helper, /UUID\.test\(user\.id\)/);
  assert.match(helper, /p_actor_auth_user_id:\s*user\.id/);
});

test("shared Build 004 authorization decision is server-role-only and fails closed", () => {
  assert.match(helper, /mme_authorize_employee_action/);
  assert.match(helper, /apikey:\s*service/);
  assert.match(helper, /Authorization:\s*`Bearer \$\{service\}`/);
  assert.match(helper, /if \(!decision\.ok\)/);
  assert.match(helper, /await decision\.json\(\) !== true/);
});

for (const routePath of routes) {
  test(`${routePath} uses the shared identity authorization gate`, () => {
    const source = readFileSync(routePath, "utf8");
    assert.match(source, /authenticateAndAuthorizeEmployee/);
    assert.match(source, /if \(!?(?:authorization|build004)\.ok\)/);
  });
}

test("legacy inspection permission checks are not mistaken for the centralized identity gate", () => {
  for (const routePath of routes.slice(1, 4)) {
    const source = readFileSync(routePath, "utf8");
    assert.match(source, /mme_employee_authorize_inventory_action/);
  }
  assert.doesNotMatch(
    readFileSync(routes[0], "utf8"),
    /mme_employee_authorize_inventory_action/,
  );
});
