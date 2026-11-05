import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/pos/transactions/[transactionId]/tenders/route.ts", import.meta.url), "utf8");

test("Tender API authenticates employee and derives actor identity server-side", () => {
  assert.match(route, /authenticatePosRequest/);
  assert.match(route, /p_actor_person_id: context\.personId/);
  assert.doesNotMatch(route, /input\.actor_person_id|input\.person_id/);
});

test("Tender API requires idempotency and a configured provider account", () => {
  assert.match(route, /idempotency-key/);
  assert.match(route, /POS_TENDER_PROVIDER/);
  assert.match(route, /POS_TENDER_PROVIDER_ACCOUNT_REFERENCE/);
  assert.match(route, /No payment has been attempted/);
});

test("Tender API accepts only allowlisted tender inputs and integer minor units", () => {
  assert.match(route, /const allowed = \[/);
  assert.match(route, /Number\.isSafeInteger\(input\.amount_minor\)/);
  assert.match(route, /\^\[A-Z\]\{3\}\$/);
  assert.doesNotMatch(route, /input\.provider|input\.provider_account_reference/);
});

test("Tender API creates intent only and does not claim provider authorization", () => {
  assert.match(route, /mme_pos_create_tender_attempt/);
  assert.match(route, /paymentAttempted: false/);
  assert.match(route, /No provider authorization or capture has been performed/);
});

test("Tender API does not accept raw cardholder data fields", () => {
  for (const field of ["pan", "card_number", "cvv", "cvc", "track_data"]) {
    assert.doesNotMatch(route, new RegExp(`["']${field}["']`, "i"));
  }
});
