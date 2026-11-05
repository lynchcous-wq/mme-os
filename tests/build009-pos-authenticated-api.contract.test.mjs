import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const auth = await readFile(new URL("../lib/pos/authenticated-server.ts", import.meta.url), "utf8");
const route = await readFile(new URL("../app/api/pos/transactions/route.ts", import.meta.url), "utf8");

test("POS authentication validates bearer sessions with Supabase Auth", () => {
  assert.match(auth, /authorization/);
  assert.match(auth, /Bearer\\s\+/i);
  assert.match(auth, /\/auth\/v1\/user/);
  assert.match(auth, /userResponse\.ok/);
});
test("POS actor identity is resolved server-side from the verified Auth subject", () => {
  assert.match(auth, /mme_resolve_person_for_auth_subject/);
  assert.match(auth, /p_auth_user_id: user\.id/);
  assert.match(route, /p_actor_person_id: context\.personId/);
  assert.doesNotMatch(route, /body as \\{[^}]*actor_person_id/);
});
test("POS create API accepts only an order ID and requires idempotency", () => {
  assert.match(route, /idempotency-key/);
  assert.match(route, /key !== "order_id"/);
  assert.match(route, /mme_pos_create_transaction/);
  assert.match(route, /Cache-Control.*no-store/);
});
test("POS API does not return raw upstream database errors", () => {
  assert.match(route, /POS transaction could not be created/);
  assert.doesNotMatch(route, /errorText\s*\}/);
});
