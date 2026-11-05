import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../app/api/catalog/[id]/units/route.ts", import.meta.url), "utf8");

test("unit route is restricted to active serialized products and in-stock units", () => {
  assert.match(source, /products\[0\]\.active !== true/);
  assert.match(source, /products\[0\]\.serialized !== true/);
  assert.match(source, /unit_status=eq\.in_stock/);
});

test("public availability never exposes serials, IMEIs, or internal location codes", () => {
  for (const field of ["serial_number", "imei", "location_code", "storage_key", "supplier_cost", "inspection_evidence"]) {
    assert.doesNotMatch(source, new RegExp(field, "i"), field + " must not be exposed");
  }
  assert.match(source, /location_name: locationById\.get\(locationId\)/);
});

test("unit availability is uncached and fails closed on unavailable data", () => {
  assert.match(source, /Cache-Control": "no-store"/);
  assert.match(source, /status: 503/);
  assert.match(source, /status: 502/);
});