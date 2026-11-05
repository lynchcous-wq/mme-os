import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const checkout = await readFile(new URL("../app/checkout/page.tsx", import.meta.url), "utf8");
const cart = await readFile(new URL("../app/cart/page.tsx", import.meta.url), "utf8");
const complete = await readFile(new URL("../app/checkout/complete/page.tsx", import.meta.url), "utf8");
const payment = await readFile(new URL("../supabase/functions/create-checkout-payment/index.ts", import.meta.url), "utf8");
const webhook = await readFile(new URL("../supabase/functions/stripe-webhook/index.ts", import.meta.url), "utf8");

test("cart only exposes checkout after server price and stock validation", () => {
  assert.match(cart, /validated && <Link className="button" href="\/checkout"/);
  assert.match(cart, /\/api\/cart\/validate/);
});

test("checkout requires a signed-in Supabase user and submits only identifiers and fulfillment details", () => {
  assert.match(checkout, /supabase\.auth\.getSession\(\)/);
  assert.match(checkout, /accessToken/);
  assert.match(checkout, /functions\/v1\/create-checkout-payment/);
  assert.match(checkout, /product_id/);
  assert.match(checkout, /serialized_unit_id/);
  assert.doesNotMatch(checkout, /price_cents:\s*line\./);
});

test("checkout uses a stable idempotency key until the customer changes checkout details", () => {
  assert.match(checkout, /crypto\.randomUUID\(\)/);
  assert.match(checkout, /x-idempotency-key/);
  assert.match(checkout, /setIdempotencyKey\(""/);
});

test("payment uses Stripe Elements and does not claim completion from a browser response", () => {
  assert.match(checkout, /PaymentElement/);
  assert.match(checkout, /stripe\.confirmPayment/);
  assert.match(checkout, /MME is verifying the payment event/);
  assert.match(complete, /not, by itself, proof that an order is paid/);
});

test("payment service verifies user identity and server-side trusted pricing", () => {
  assert.match(payment, /auth\.getUser\(\)/);
  assert.match(payment, /MME_CHECKOUT_PRICING_URL/);
  assert.match(payment, /mme_create_mixed_order_and_reserve/);
  assert.match(payment, /mme_bind_order_payment_intent/);
  assert.match(payment, /idempotencyKey/);
});

test("webhook path verifies Stripe signature before payment processing", () => {
  assert.match(webhook, /verifyStripeWebhook/);
  assert.match(webhook, /mme_process_verified_payment_event/);
  assert.match(webhook, /mme_record_return_refund_event/);
});
