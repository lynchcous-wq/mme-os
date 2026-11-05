import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = async (name) => readFile(new URL("../supabase/migrations/" + name, import.meta.url), "utf8");

test("Build 001 catalog schema is present before commerce link and inventory consumers", async () => {
  const catalog = await migration("20261103000001_catalog_integration_product_catalog.sql");
  const commerce = await migration("20261103000600_build001_inventory_orders.sql");
  const link = await migration("20261103007400_build001_catalog_commerce_link_guard.sql");
  assert.match(catalog, /create table public\.products/);
  assert.match(catalog, /create table public\.product_categories/);
  assert.match(commerce, /create table public\.mme_products/);
  assert.match(link, /add column catalog_product_id uuid/);
  assert.match(link, /mme_require_published_catalog_product/);
});

test("inventory and serialized dependencies include reservations, device rows, and inspection holds", async () => {
  const inventory = await migration("20261103000600_build001_inventory_orders.sql");
  const reservations = await migration("20261103000700_build001_reservation_lifecycle.sql");
  const units = await migration("20261103000800_build001_serialized_units.sql");
  const checkout = await migration("20261103000900_build001_serialized_checkout.sql");
  const receiving = await migration("20261103001000_build001_receiving_adjustments_transfers.sql");
  const inspection = await migration("20261103001100_build001_inspection_damage_repair_quarantine.sql");
  assert.match(inventory, /create table public\.mme_inventory_balances/);
  assert.match(reservations, /mme_inventory_reservations/);
  assert.match(units, /create table public\.mme_serialized_units/);
  assert.match(units, /serial_number text not null/);
  assert.match(checkout, /add column serialized_unit_id/);
  assert.match(receiving, /average_unit_cost_cents/);
  assert.match(inspection, /create table public\.mme_inventory_inspections/);
});

test("serialized disposition ledger remains append-only and private", async () => {
  const ledger = await migration("20261103008200_build001_serialized_unit_disposition_ledger.sql");
  const immutable = await migration("20261103008300_build001_immutable_serialized_disposition_ledger.sql");
  assert.match(ledger, /create table public\.mme_serialized_unit_dispositions/);
  assert.match(ledger, /enable row level security/);
  assert.match(immutable, /before update or delete/);
  assert.match(immutable, /revoke insert,update,delete,truncate/);
});

test("Build 008 integration branch does not import unrelated Build 006 migration files", async () => {
  await assert.rejects(
    readFile(new URL("../supabase/migrations/20261104000100_build006_task_foundation.sql", import.meta.url), "utf8"),
    { code: "ENOENT" },
  );
});
