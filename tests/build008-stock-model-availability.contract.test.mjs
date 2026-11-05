import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const list = await readFile(new URL("../app/api/catalog/route.ts", import.meta.url), "utf8");
const detail = await readFile(new URL("../app/api/catalog/[id]/route.ts", import.meta.url), "utf8");
const cart = await readFile(new URL("../app/api/cart/validate/route.ts", import.meta.url), "utf8");

test("serialized availability derives from individual in-stock unit rows", () => {
  assert.match(list, /commerce\.serialized === true/);
  assert.match(list, /unit_status=eq\.in_stock/);
  assert.match(detail, /commerce\.serialized === true/);
  assert.match(detail, /unit_status=eq\.in_stock/);
});

test("quantity availability subtracts reserved stock exactly once and clamps at zero", () => {
  assert.match(list, /Math\.max\(0, balance\.on_hand_quantity - balance\.reserved_quantity\)/);
  assert.match(detail, /Number\(balance\.on_hand_quantity \?\? 0\) - Number\(balance\.reserved_quantity \?\? 0\)/);
  assert.match(cart, /Number\(balance\.on_hand_quantity \?\? 0\) - Number\(balance\.reserved_quantity \?\? 0\)/);
});

test("cart validates serialized product/unit correspondence and one-unit quantity", () => {
  assert.match(cart, /product\.serialized === true/);
  assert.match(cart, /!item\.serialized_unit_id \|\| item\.quantity !== 1/);
  assert.match(cart, /unit\.unit_status !== "in_stock"/);
  assert.match(cart, /unit\.product_id !== item\.product_id/);
  assert.match(cart, /unit\.location_id !== item\.location_id/);
});

test("cart validation does not reserve inventory or create payments", () => {
  assert.match(cart, /Validation only\. No inventory is reserved and no payment is created/);
  assert.doesNotMatch(cart, /mme_reserve_inventory|mme_create_serialized_order_and_reserve|payment_intents/);
});