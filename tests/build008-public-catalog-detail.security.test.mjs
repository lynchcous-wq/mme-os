import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../app/api/catalog/[id]/route.ts", import.meta.url), "utf8");

test("detail route validates product UUID and only resolves published catalog products", () => {
  assert.match(source, /uuidPattern\.test\(id\)/);
  assert.match(source, /catalog_status=eq\.published/);
  assert.match(source, /status: 404/);
});

test("detail media response excludes storage keys and internal identifiers", () => {
  assert.match(source, /media:\s*media[\s\S]*?\.map\(\(item\) => \(\{/);
  assert.doesNotMatch(source, /storage_key|location_code|serial_number|imei|supplier_cost|employee_identity|inspection_evidence/i);
  assert.match(source, /external_url: item\.external_url/);
  assert.match(source, /alt_text: item\.alt_text/);
});

test("detail route does not cache live catalog responses", () => {
  assert.match(source, /Cache-Control": "no-store"/);
});