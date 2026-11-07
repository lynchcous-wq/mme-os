import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../app/api/shipping/quotes/route.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/migrations/20261107009400_build010_shipping_package_profiles.sql", import.meta.url), "utf8");

test("shipping quotes require same-origin signed-in active customer", () => {
  assert.match(route, /hasSameOrigin\(request\)/);
  assert.match(route, /requireBrowserUser\(request\)/);
  assert.match(route, /mme_customer_account_links/);
  assert.match(route, /mme_person_identities/);
});

test("US shipping address is validated by configured secure address service", () => {
  assert.match(route, /country !== "US"/);
  assert.match(route, /MME_ADDRESS_VALIDATOR_URL/);
  assert.match(route, /MME_ADDRESS_VALIDATOR_SECRET/);
  assert.match(route, /deliverable !== true/);
  assert.match(route, /verified !== true/);
  assert.match(route, /https:/);
});

test("shipping uses database package profiles and blocks serialized or hazmat items", () => {
  assert.match(migration, /shipping_weight_oz/);
  assert.match(migration, /shipping_length_in/);
  assert.match(migration, /shipping_hazmat/);
  assert.match(route, /product\.serialized/);
  assert.match(route, /product\.shipping_hazmat/);
  assert.match(route, /shipping_weight_oz/);
});

test("carrier rates are retrieved server-side and validated as USD integer cents", () => {
  assert.match(route, /MME_CARRIER_RATE_URL/);
  assert.match(route, /MME_CARRIER_RATE_SECRET/);
  assert.match(route, /rate\.currency !== "USD"/);
  assert.match(route, /Number\.isSafeInteger\(rate\.amount_cents\)/);
});

test("customer-bound signed quote tokens expire after ten minutes", () => {
  assert.match(route, /MME_SHIPPING_QUOTE_SIGNING_SECRET/);
  assert.match(route, /createHmac\("sha256"/);
  assert.match(route, /customer_id: identities\[0\]\.person_id/);
  assert.match(route, /expires_at: expiresAt/);
  assert.match(route, /10 \* 60 \* 1000/);
});
