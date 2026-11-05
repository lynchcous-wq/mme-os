import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const eventRoute = await readFile(new URL("../app/api/pos/transactions/[transactionId]/events/route.ts", import.meta.url), "utf8");
const viewRoute = await readFile(new URL("../app/api/pos/transactions/[transactionId]/route.ts", import.meta.url), "utf8");

test("POS event API derives actor identity from verified session", () => {
  assert.match(eventRoute, /authenticatePosRequest/);
  assert.match(eventRoute, /p_actor_person_id: context\.personId/);
  assert.doesNotMatch(eventRoute, /input\.actor_person_id|input\.person_id/);
});
test("POS event API requires idempotency and optimistic revision", () => {
  assert.match(eventRoute, /idempotency-key/);
  assert.match(eventRoute, /expected_revision/);
  assert.match(eventRoute, /p_expected_revision: input\.expected_revision/);
});
test("POS event API validates event types and hides upstream errors", () => {
  assert.match(eventRoute, /eventTypes/);
  assert.doesNotMatch(eventRoute, /"tender_result"|"reconciliation_result"|"pricing_confirmed"|"finalization_confirmed"/);
  assert.match(eventRoute, /nextStatuses/);
  assert.match(eventRoute, /POS transaction event could not be recorded/);
  assert.doesNotMatch(eventRoute, /detail\s*\}/);
});
test("POS history API checks view permission before returning events", () => {
  assert.match(viewRoute, /mme_person_authorize_pos_action/);
  assert.match(viewRoute, /pos\.transaction\.view/);
  assert.match(viewRoute, /permission\.json\(\) !== true/);
  assert.doesNotMatch(viewRoute, /select=[^`]*actor_person_id/);
  assert.doesNotMatch(viewRoute, /select=id,revision,event_type,previous_status,next_status,actor_person_id/);
  assert.match(viewRoute, /Cache-Control.*no-store/);
});
