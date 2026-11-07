import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const cart = await readFile(new URL("../app/cart/page.tsx", import.meta.url), "utf8");
const catalog = await readFile(new URL("../app/products/page.tsx", import.meta.url), "utf8");
const validator = await readFile(new URL("../app/api/cart/validate/route.ts", import.meta.url), "utf8");

test("storefront exposes add-to-cart for non-serialized inventory only", () => {
  assert.match(catalog, /mme-shopping-cart-v1/);
  assert.match(catalog, /Add to cart/);
  assert.match(catalog, /product\.serialized/);
  assert.match(catalog, /Individually tracked devices require unit selection/);
});

test("cart supports quantity changes, line removal and live validation", () => {
  assert.match(cart, /changeQuantity/);
  assert.match(cart, /function remove/);
  assert.match(cart, /\/api\/cart\/validate/);
  assert.match(cart, /Refresh price & availability/);
});

test("cart validation checks published products, active locations and inventory", () => {
  assert.match(validator, /catalog_status=eq\.published/);
  assert.match(validator, /on_hand_quantity/);
  assert.match(validator, /reserved_quantity/);
  assert.match(validator, /unit_price_cents/);
});

test("cart validation explicitly does not reserve stock or create a payment", () => {
  assert.match(validator, /Validation only\. No inventory is reserved and no payment is created\./);
  assert.doesNotMatch(cart, /\/api\/checkout/);
});
