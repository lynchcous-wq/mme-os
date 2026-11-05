import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../app/api/catalog/route.ts", import.meta.url), "utf8");

test("list route only selects active commerce products linked to published catalog records", () => {
  assert.match(source, /active=eq\.true/);
  assert.match(source, /catalog_status=eq\.published/);
  assert.match(source, /catalogById\.get\(commerce\.catalog_product_id\)/);
  assert.match(source, /if \(!catalog\) return \[\]/);
});

test("list route projects public fields and excludes private location and device identifiers", () => {
  assert.match(source, /location_name: location\.display_name/);
  assert.match(source, /available_quantity: Math\.max\(0, balance\.on_hand_quantity - balance\.reserved_quantity\)/);
  for (const field of ["location_code", "serial_number", "imei", "supplier_cost", "storage_key", "employee_identity", "inspection_evidence"]) {
    assert.doesNotMatch(source, new RegExp(field, "i"), field + " must not be exposed");
  }
});

test("list route is uncached and fails closed when configuration or upstream data is unavailable", () => {
  assert.match(source, /status: 503/);
  assert.match(source, /status: 502/);
  assert.match(source, /Cache-Control": "no-store"/);
});