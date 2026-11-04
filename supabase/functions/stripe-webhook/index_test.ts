import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
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

Deno.test("sha256Hex returns a stable SHA-256 digest", async () => {
  assertEquals(await sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

Deno.test("verifyStripeWebhook rejects an invalid signature", async () => {
  await assertRejects(
    () => verifyStripeWebhook("{}", "t=1,v1=invalid", "whsec_test_invalid", "sk_test_unit_test"),
  );
});
