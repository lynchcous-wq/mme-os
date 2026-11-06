import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/20261103006600_build001_atomic_pricing_quote_reservation.sql", import.meta.url), "utf8");
const checkout = await readFile(new URL("../supabase/functions/create-checkout-payment/index.ts", import.meta.url), "utf8");

test("atomic order RPC accepts an expected quoted subtotal", () => {
  assert.match(migration, /p_expected_subtotal_cents bigint/);
  assert.match(migration, /p_expected_subtotal_cents is null or p_expected_subtotal_cents<0/);
});

test("subtotal comparison runs after locked live product prices are read and before order insertion", () => {
  const compare = migration.indexOf("if v_subtotal<>p_expected_subtotal_cents then");
  const insert = migration.indexOf("insert into public.mme_orders");
  assert.ok(compare > 0 && insert > compare, "subtotal mismatch must abort before order/reservation creation");
  assert.match(migration, /for update of u,p/);
  assert.match(migration, /where p\.id=v_item\.product_id for update/);
  assert.match(migration, /Quoted subtotal changed; refresh cart before checkout/);
});

test("legacy RPC overload cannot bypass atomic quote validation", () => {
  assert.match(migration, /mme_create_mixed_order_and_reserve\(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,timestamptz\) from public,anon,authenticated,service_role/);
  assert.match(migration, /mme_create_mixed_order_and_reserve\(text,uuid,text,jsonb,bigint,bigint,bigint,jsonb,bigint,timestamptz\) to service_role/);
});

test("checkout passes quoted subtotal to atomic RPC and reads database subtotal", () => {
  assert.match(checkout, /p_expected_subtotal_cents: priced\.expected_subtotal_cents/);
  assert.match(checkout, /select\("id,subtotal_cents,total_cents,currency,status,customer_identity_id"\)/);
  assert.match(checkout, /order\.subtotal_cents !== priced\.expected_subtotal_cents/);
});
