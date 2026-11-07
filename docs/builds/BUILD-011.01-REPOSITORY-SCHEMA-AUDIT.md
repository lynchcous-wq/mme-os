# Build 011.01 — Repository Schema and Migration Audit

Status: **repository audit completed; live Supabase verification blocked**.
Branch: `implementation/build-011-purchasing-receiving-integration`.
Audit date: 2026-11-07.

## Scope and evidence boundary

This audit inspected the GitHub default branch, isolated purchasing/receiving implementation branches, PR metadata and migration SQL. It did not connect to the live Supabase project. No Supabase database-query/management connector or database credentials are available in this execution context. Therefore this report does not assert which migrations are applied remotely, what tables exist in production, whether RLS is enabled remotely, or whether production data is present.

## Default branch finding

The `main` branch currently exposes only one file under `supabase/migrations`:

- `20261105001800_build010_warranty_security_operations_dashboard.sql`

The default branch has no committed purchasing/receiving migration chain in that directory. This is a repository observation, not a live database inventory. The migration file itself creates warranty/security dashboard snapshot storage and a service-role summary function; it is not a procurement schema.

## Existing isolated migration chains

### 009.57–009.59 (PRs #53–#55)

These draft PRs introduce a coherent-looking staged procurement path:

- `mme_procurement_vendors`, `mme_procurement_vendor_quotes`, budgets, purchase requests, allocations, internal PO drafts and vendor performance/audit.
- `mme_receiving_sessions`, lines, serial registry, discrepancies, landed-cost evidence, intake staging, AP match records and receiving audit.
- `mme_inventory_ledger`, `mme_inventory_balances`, cost layers, adjustment requests, reconciliation and audit.
- Receiving explicitly stages accepted goods and says it does not directly mutate inventory. A separate authorized inventory-ledger receipt posting is intended.

The PRs are all open/draft and have not been merged. Their test files are static SQL text-contract tests; they are not evidence of PostgreSQL migration replay, live RLS behavior, concurrency safety in a running database, or production deployment.

### 010.41 — Purchasing/Vendor Management

Its migration `20261106002330_build010_purchasing_vendor_management.sql` creates a different schema family:

- `mme_vendors`, `mme_vendor_contacts`, `mme_purchase_orders`, `mme_purchase_order_lines`, `mme_vendor_invoices`, `mme_purchase_order_events`.
- It also defines `mme_purchase_order_receive_line`, which directly increments `mme_inventory_balances`, inserts `mme_inventory_movements`, and updates PO received quantity/status in one function.

**Critical conflict:** this direct receiving-to-balance/movement path bypasses the staged receiving and separate inventory-ledger posting boundary described by 009.58/009.59. It must not be enabled alongside the staged path as a second stock-posting authority.

The migration relies on pre-existing `mme_inventory_locations`, `mme_inventory_products`, `mme_inventory_balances` and `mme_inventory_movements`; existence and production definitions have not been verified in the live database.

### 010.70 — Vendor Catalog / Price Intelligence

Its migration `20261106005000_build010_vendor_catalog_price_intelligence.sql` uses:

- `mme_financial_vendors` as the vendor foreign-key target.
- `mme_inventory_items` for canonical inventory mapping.
- `mme_vendor_catalog_items`, `mme_vendor_catalog_offers`, and `mme_vendor_quote_lines`.

**Critical conflicts:** the vendor master differs from both 009.57's `mme_procurement_vendors` and 010.41's `mme_vendors`. Product references use `mme_inventory_items`, whereas 010.41 uses `mme_inventory_products`. The foreign-key dependencies and canonical product identity are not reconciled.

### 010.71 — Intelligent Purchasing

Its migration `20261106005100_build010_intelligent_purchasing.sql` adds price observations and landed-cost scenarios referencing `mme_vendor_catalog_offers`, and its PR says tests were not executed, migration not applied, not merged and not deployed.

It extends the 010.70 vendor catalog branch, not the 009.57 procurement quote schema directly. It must be integrated only after the catalog and vendor master are reconciled.

## Findings requiring resolution before schema implementation

| Finding | Risk | Required resolution |
|---|---|---|
| Three vendor masters: `mme_procurement_vendors`, `mme_vendors`, `mme_financial_vendors` | Duplicate suppliers, broken references, inconsistent approval state | Select one canonical vendor identity and map/merge references |
| Two product masters: `mme_inventory_products`, `mme_inventory_items` | Duplicate SKUs and disconnected stock records | Select canonical product identity and map supplier SKU to it |
| Multiple stock models: `mme_inventory_balances/movements` and `mme_inventory_ledger/balances` | Double posting, inaccurate quantity/value | Select exactly one ledger and one balance projection |
| Direct PO receipt posting in 010.41 vs staged receiving in 009.58/009.59 | Duplicate receipt and bypassed inspection | Retire/disable the direct mutation path in the integrated design; route through one controlled intake-to-ledger posting operation |
| Different actor identity conventions (`created_by`, `created_by_auth_user_id`, actor UUID parameters) | Spoofable actor attribution / inconsistent audit | Resolve actor server-side from trusted MME identity and permissions; do not trust request body actor IDs |
| PR checks are text-contract tests | False confidence about SQL correctness | Run migration replay, database integration, RLS, grants, concurrency, idempotency and rollback tests on a disposable Supabase environment |
| Remote database migration state unavailable | Cannot safely choose next migration number or assume remote objects | Obtain read-only live schema and migration history before generating/applying migrations |

## Decisions for Build 011

1. Do not merge PRs #53–#55 or the 010.41/010.70/010.71 branches wholesale.
2. Preserve their build history and useful code as source material; do not delete or renumber them.
3. The target architecture remains: vendor/product mapping -> approved PO -> receiving intake/inspection -> discrepancy resolution -> one idempotent inventory-ledger posting -> invoice match -> separately authorized AP/payment.
4. Keep vendor invoice matching separate from payment execution.
5. The final design must use the existing MME person/employee identity and permission authority, not client-supplied actor IDs or unverified role claims.
6. No production migration, database mutation, merge, or deployment is authorized by this audit.

## Next required input / gate

To finish the live database audit, an authorized read-only Supabase connection is required. Retrieve:

- applied migration history (including migration version and name);
- table/column/constraint/index definitions for vendor, catalog, PO, receiving, stock and identity entities;
- foreign-key dependencies;
- RLS enabled state, policies, grants and security-definer function definitions;
- relevant existing product/location/stock counts, using aggregate counts only and no customer/employee PII.

Until that read-only inspection is available, the live-schema audit remains **blocked** and no SQL migration should be generated on assumptions.

## 011.01 acceptance status

- [x] Default-branch migration inventory
- [x] Existing PR and branch migration inventory
- [x] Vendor/product/stock schema conflict analysis
- [x] Duplicate stock-posting path identified
- [x] Live database access limitation documented
- [ ] Read-only live Supabase schema and migration history verified
- [ ] Canonical schema decision approved against live objects
- [ ] Disposable-database migration replay and integration test plan validated

**Result:** Repository audit completed; 011.01 is not fully closed until the live Supabase verification and canonical-source decision are completed.
