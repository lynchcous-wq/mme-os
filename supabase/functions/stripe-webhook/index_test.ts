import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import Stripe from "npm:stripe@17.7.0";
import { readBoundedBody, sha256Hex, verifyStripeWebhook } from "../_shared/stripe-webhook-security.ts";

Deno.test("readBoundedBody accepts a body within its byte limit", async () => {
  const body = await readBoundedBody(new Request("https://example.test", { method: "POST", body: "payload" }), 7);
  assertEquals(body, "payload");
});

Deno.test("readBoundedBody rejects a body exceeding its byte limit", async () => {
  const body = await readBoundedBody(new Request("https://example.test", { method: "POST", body: "payload!" }), 7);
  assertEquals(body, null);
});

Deno.test("readBoundedBody rejects an empty request", async () => {
  const body = await readBoundedBody(new Request("https://example.test", { method: "POST", body: "" }), 7);
  assertEquals(body, null);
});

Deno.test("readBoundedBody accepts a body exactly at its byte limit", async () => {
  const body = await readBoundedBody(new Request("https://example.test", { method: "POST", body: "1234567" }), 7);
  assertEquals(body, "1234567");
});

Deno.test("readBoundedBody rejects invalid UTF-8 instead of throwing", async () => {
  const request = new Request("https://example.test", {
    method: "POST",
    body: new Uint8Array([0xc3, 0x28]),
  });
  const body = await readBoundedBody(request, 2);
  assertEquals(body, null);
});

Deno.test("sha256Hex returns a stable SHA-256 digest", async () => {
  assertEquals(await sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

Deno.test("verifyStripeWebhook rejects an invalid signature", async () => {
  await assertRejects(
    () => verifyStripeWebhook("{}", "t=1,v1=invalid", "whsec_test_invalid", "sk_test_unit_test"),
  );
});

const testSecret = "whsec_build001_test_secret";
const testStripe = new Stripe("sk_test_build001_unit_test", { apiVersion: "2025-02-24.acacia" });
const validEventPayload = JSON.stringify({
  id: "evt_build001_webhook_test",
  object: "event",
  api_version: "2025-02-24.acacia",
  created: Math.floor(Date.now() / 1000),
  data: { object: { id: "pi_build001_test", object: "payment_intent" } },
  livemode: false,
  pending_webhooks: 1,
  request: { id: null, idempotency_key: null },
  type: "payment_intent.succeeded",
});

Deno.test("verifyStripeWebhook accepts a correctly signed event", async () => {
  const signature = testStripe.webhooks.generateTestHeaderString({
    payload: validEventPayload,
    secret: testSecret,
  });
  const event = await verifyStripeWebhook(validEventPayload, signature, testSecret, "sk_test_build001_unit_test");
  assertEquals(event.id, "evt_build001_webhook_test");
  assertEquals(event.type, "payment_intent.succeeded");
});

Deno.test("verifyStripeWebhook rejects a body changed after signing", async () => {
  const signature = testStripe.webhooks.generateTestHeaderString({
    payload: validEventPayload,
    secret: testSecret,
  });
  await assertRejects(() =>
    verifyStripeWebhook(validEventPayload + " ", signature, testSecret, "sk_test_build001_unit_test")
  );
});

Deno.test("verifyStripeWebhook rejects a stale signature timestamp", async () => {
  const signature = testStripe.webhooks.generateTestHeaderString({
    payload: validEventPayload,
    secret: testSecret,
    timestamp: Math.floor(Date.now() / 1000) - 600,
  });
  await assertRejects(() =>
    verifyStripeWebhook(validEventPayload, signature, testSecret, "sk_test_build001_unit_test")
  );
});
