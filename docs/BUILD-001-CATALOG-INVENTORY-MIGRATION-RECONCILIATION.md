# Build 001 catalog and inventory migration reconciliation

Status: design gate only. No database migration has been applied.

## CI baseline

- Inventory/order PR #11 commit `864ce55ff22689add4b1f40a093a2cd8d663f6aa`: Deno Edge Function type-check, TypeScript check, and production build passed in workflow run 41875841179.
- Catalog PR #12 commit `24fa0d2252579c58d3b0354fd96b5d407723788f`: migration version check, catalog API security guard check, TypeScript validation, and production build passed in workflow run 41728269341.
- These checks ran on separate branches; they do not validate the combined migration set.

## Confirmed migration collision

PR #12 owns migration versions `20261103000100` through `20261103000800`.
PR #11 begins at `20261103000600` and includes 59 inventory/order migrations through `20261103006500`.
The combined history cannot contain duplicate migration versions. Renumber PR #11 only after preserving its internal ordering and confirming no external references rely on the old filenames.

## Confirmed schema overlap

PR #12 creates a catalog domain:
- `public.product_categories`
- `public.products`
- `public.product_media`
- `public.product_catalog_events`

Its `public.products` row owns category, SKU, slug, descriptive/specification fields, condition, tracking mode, catalog approval/publication state, and creator/reviewer metadata.

PR #11 creates a commerce/inventory domain:
- `public.mme_store_locations`
- `public.mme_products`
- `public.mme_inventory_balances`
- `public.mme_orders` and immutable order lines
- inventory reservations and payment-event ledger

Its `public.mme_products` row owns SKU, title, description, category key, condition grade, authoritative unit price in cents, currency, serialized flag, and active state.

The two product tables have independently unique SKU values and no foreign-key relationship. This is not just a filename collision: merging both branches without a product identity strategy would create two unlinked product records.

## Proposed integration model (requires disposable-database proof)

Keep the domains distinct but explicitly linked:
1. `public.products` is the catalog/content and employee approval record.
2. `public.mme_products` is the sellable commerce/inventory record and owns the authoritative checkout price.
3. Add a nullable, unique `catalog_product_id` foreign key from `mme_products` to `products`, with an explicit audited mapping workflow. Do not infer or auto-link records solely because SKUs happen to match.
4. Enforce SKU consistency for linked rows and prevent deletion of catalog records referenced by sellable products.
5. Checkout continues to read price only from the commerce record; catalog approval/publication controls storefront eligibility. A product must not be purchasable merely because an inventory row exists.
6. Define the exact behavior for draft, pending approval, changes requested, published, archived, and inactive commerce products before enabling public listing or checkout.

## Migration sequence proposal

- Keep PR #12 catalog migrations at `20261103000100`–`20261103000800`.
- Renumber PR #11's 59 migrations, in their existing dependency order, into a non-overlapping sequence beginning at `20261103000900`.
- Add the catalog/commerce link only after both product tables exist, as a new final additive migration.
- Inspect all migration filename references, seed scripts, tests, docs, and Supabase migration history before changing filenames.

## Release gates

- Build a disposable Supabase project or isolated local database from an empty schema.
- Apply the consolidated migration set in order; verify every migration succeeds.
- Run pgTAP and regression tests for catalog authorization, order creation, aggregate and serialized reservations, mixed-cart atomicity, payment-intent binding, webhook replay/idempotency, expiry/release, and refund/dispute transitions.
- Add cross-domain tests proving unpublished/archived products cannot be sold and linked SKU/price changes follow the agreed ownership rules.
- Deploy Edge Functions to a test project and complete Stripe test-mode end-to-end validation.
- Do not apply migrations to production or enable live Stripe checkout until every gate passes.

## Explicitly not done

No migration was renumbered, no product tables were merged, no SQL was applied to Supabase, no Edge Function was deployed, and no live payment capability was enabled.
