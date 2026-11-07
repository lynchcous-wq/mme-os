import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/webhooks/stripe/checkout/route.ts", import.meta.url), "utf8");

test("Checkout webhook verifies Stripe timestamped HMAC signatures", () => {
  assert.match(route, /createHmac\("sha256"\)/);
  assert.match(route, /timingSafeEqual/);
  assert.match(route, /Date\.now\(\).*300/);
  assert.match(route, /stripe-signature/);
});

test("Checkout webhook limits payload size and rejects invalid signatures", () => {
  assert.match(route, /MAX_BODY_BYTES/);
  assert.match(route, /status: 413/);
  assert.match(route, /status: 400/);
});

test("Checkout completion does not mark unpaid asynchronous sessions as paid", () => {
  assert.match(route, /eventType === "checkout\.session\.completed" && session\.payment_status !== "paid"/);
  assert.match(route, /awaiting_async_payment: true/);
});

test("Only recognized USD payment-session events reach the service-role RPC", () => {
  assert.match(route, /session\.mode !== "payment"/);
  assert.match(route, /checkout\.session\.async_payment_succeeded/);
  assert.match(route, /checkout\.session\.async_payment_failed/);
  assert.match(route, /checkout\.session\.expired/);
  assert.match(route, /currency !== "usd"/);
  assert.match(route, /mme_process_order_payment_event/);
});

test("Order linkage comes from server-created Checkout Session metadata", () => {
  assert.match(route, /session\.metadata\?\.mme_order_id/);
  assert.match(route, /p_order_id: orderId/);
  assert.match(route, /p_payload_sha256: payloadHash/);
});
