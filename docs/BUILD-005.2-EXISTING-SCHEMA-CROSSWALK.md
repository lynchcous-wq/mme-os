# Build 005.2 — Existing Schema Crosswalk

**Company:** Much More Electronics  
**Build:** 005 — Inventory Core  
**Stage:** 005.2 — Existing schema and responsibility crosswalk  
**Status:** Repository inspection artifact; no database schema change  
**Branch:** `implementation/build-005-inventory-core`  
**Baseline inspected:** `implementation/build-004-supabase-identity-foundation`

## 1. Inspection evidence

The inspected repository baseline contains:

- `docs/BUILD-001-ARCHITECTURE.md`: enterprise module registry and target architecture. It explicitly describes a planning baseline, not proof of implementation.
- `docs/BUILD-002-MASTER-ARCHITECTURE.md`: target module boundaries and data ownership; it explicitly says the repository is a storefront shell with placeholder routes.
- `docs/BUILD-008-ENTERPRISE-INVENTORY.md`: detailed inventory/product-intelligence specification, explicitly not implemented.
- `app/page.tsx`, `app/products/page.tsx`, and `app/account/page.tsx`: existing storefront/account route files; route presence alone does not establish persisted inventory or order workflows.
- `package.json`: Next.js, React and TypeScript dependencies; no database client, ORM, or migration framework is declared in this manifest.
- `supabase/migrations/`: five identity-related SQL migrations (00100 through 00500) on the inspected baseline. No inventory/catalog/order/location/stock migration was present in the inspected repository tree.
- Build 004 identity foundation is a separate domain. Its tables and security controls must be preserved; inventory must not reuse identity tables for product, unit, stock, or order records.

This inspection did not connect to Supabase or query the live database. The user previously confirmed that ten identity tables exist in the development Supabase project. That does not establish whether unrelated inventory/order tables exist in that database. A database-side inventory schema inventory remains required before any migration is authored or applied.

## 2. Crosswalk

| Existing artifact or domain | Responsibility indicated by evidence | Decision for Build 005 | Migration impact |
|---|---|---|---|
| Build 001 enterprise architecture | Defines Catalog, Inventory, Acquisition/Pricing, POS, Orders, Returns, Shipping and BI as separate capabilities | Reuse as governance baseline; do not merge their ownership boundaries | None |
| Build 002 master architecture | Requires authoritative writers and controlled module interfaces; no direct cross-module writes | Reuse; Inventory owns stock state, not order/payment/pricing state | None |
| Build 008 inventory specification | Defines detailed target inventory lifecycle and product intelligence | Reuse and reconcile with Build 005 stages; Build 005 establishes the core data foundation, Build 008 remains the broader module specification | No automatic migration; avoid duplicate implementation |
| Existing storefront routes | UI shell / placeholder routes according to architecture documentation | Preserve routes and behavior; do not infer they contain persisted product or stock data | No route replacement |
| `package.json` | Current declared application dependencies | Do not add a DB client or ORM until backend and migration-tool decisions are reviewed | No dependency change in this stage |
| Existing Supabase identity tables | Person identity, customer/employee relationships, roles, grants, entitlements, appearance and identity audit | Reuse only for actor identity and authorization references through approved server-side services | No identity-table alteration |
| Existing identity migrations 00100–00500 | Identity foundation, auth trigger, identity audit, security lock, trigger execution restriction | Preserve; inventory migrations must be separately named, ordered, reviewed and additive | No change |
| Product Catalog (planned) | Product family, public product attributes, specs, media metadata and catalog versions | Separate catalog product from SKU and physical inventory unit | Candidate new domain; schema existence unverified |
| Inventory Management (planned) | Unit/quantity, status, location, reservation, movements and availability | Inventory service is the authoritative writer for stock and availability | Candidate new domain; schema existence unverified |
| Acquisition / COGS (planned) | Purchase/auction batch, item-level cost evidence and allocation method | Store references to approved acquisition cost evidence; do not make Inventory the pricing authority | Cross-domain references only |
| Pricing (planned) | Approved selling price and markdown versions | Consume approved price versions; never author price from Inventory | No pricing-table mutation |
| POS / Orders (planned) | Sale/order transaction and fulfillment coordination | Accept authorized reserve/commit/release commands; order remains owned by Order/POS service | Integration contract required |
| Returns / Build 017 (planned dependency) | Return authorization, inspection and disposition | Inventory changes disposition only after an authorized return outcome | Verify Build 017 before integration |
| Shipping / Pickup (planned) | Shipment, local delivery and pickup lifecycle | Consume inventory reservations and location handoffs; does not directly rewrite stock | Integration contract required |
| Analytics / Build 006 workflows | Read-only reporting and event-driven tasks/notifications | Publish minimized events/read models; analytics and alerts do not mutate stock | Event contracts required |

## 3. Canonical responsibility decisions

1. **Catalog Product:** stable product identity and reusable descriptive/specification data.
2. **SKU / sellable variant:** sellable configuration and inventory policy; distinct from the general catalog product.
3. **Physical Inventory Unit:** uniquely tracked serialized device or non-serialized quantity unit, with condition and current state.
4. **Inventory Location:** showroom, warehouse, restricted stockroom, receiving, inspection, quarantine, damaged, shipping staging and pickup locations.
5. **Movement Ledger:** append-only record of receipts, transfers, reservations, commits, returns, adjustments and dispositions. Corrections are compensating events, not edits that erase history.
6. **Reservation:** time-bounded, idempotent hold with an explicit owner/reference and expiry/release policy; concurrency-safe to prevent overselling.
7. **Acquisition / Cost Evidence:** source and item-specific landed-cost evidence remain attributable to Acquisition/COGS and Accounting valuation policy. No equal allocation across unrelated items by default.
8. **Approved Price:** remains owned by Pricing and CEO-approved policy; Inventory only consumes the current approved version.
9. **Order / Payment / Refund:** remain separate authoritative states. A payment success, refund, order close or browser redirect must not independently imply a stock disposition.
10. **Restricted identifiers:** serial/IMEI access is purpose-limited, masked in ordinary views and excluded from public payloads, labels by default, ordinary logs and source control.

## 4. Unverified items requiring database-side discovery

Before SQL is designed, inspect the development Supabase database for:

- Existing tables, views, materialized views, sequences, enums and functions related to product, catalog, SKU, inventory, stock, location, warehouse, receiving, reservation, order, sale, transfer, count and movement.
- Existing constraints, indexes, triggers, foreign keys and ownership.
- RLS enabled/forced status, policies, table grants and sequence/function grants.
- Existing migration history and whether any manually created objects are not represented in Git.
- Whether application runtime uses an owner-level connection or a restricted server role.

The repository tree alone cannot prove the live database is empty. Do not apply a new inventory migration until this comparison is complete.

## 5. Safe discovery SQL — read only

Run in the **development** Supabase SQL Editor. This query only lists matching public-schema relations; it does not create, alter or delete anything.

```sql
select
  n.nspname as schema_name,
  c.relname as object_name,
  case c.relkind
    when 'r' then 'table'
    when 'p' then 'partitioned_table'
    when 'v' then 'view'
    when 'm' then 'materialized_view'
    when 'S' then 'sequence'
    when 'f' then 'foreign_table'
    else c.relkind::text
  end as object_type,
  pg_get_userbyid(c.relowner) as object_owner,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r','p','v','m','S','f')
  and (
    c.relname ilike '%product%'
    or c.relname ilike '%catalog%'
    or c.relname ilike '%sku%'
    or c.relname ilike '%invent%'
    or c.relname ilike '%stock%'
    or c.relname ilike '%location%'
    or c.relname ilike '%warehouse%'
    or c.relname ilike '%receiv%'
    or c.relname ilike '%reserv%'
    or c.relname ilike '%order%'
    or c.relname ilike '%sale%'
    or c.relname ilike '%transfer%'
    or c.relname ilike '%count%'
    or c.relname ilike '%movement%'
  )
order by n.nspname, c.relname;
```

Then inspect columns for any returned objects before deciding reuse/extension:

```sql
select
  table_schema,
  table_name,
  ordinal_position,
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and (
    table_name ilike '%product%'
    or table_name ilike '%catalog%'
    or table_name ilike '%sku%'
    or table_name ilike '%invent%'
    or table_name ilike '%stock%'
    or table_name ilike '%location%'
    or table_name ilike '%warehouse%'
    or table_name ilike '%receiv%'
    or table_name ilike '%reserv%'
    or table_name ilike '%order%'
    or table_name ilike '%sale%'
    or table_name ilike '%transfer%'
    or table_name ilike '%count%'
    or table_name ilike '%movement%'
  )
order by table_name, ordinal_position;
```

## 6. Exit criteria for Stage 005.2

- [x] Repository tree and architecture specifications inspected.
- [x] Existing identity foundation isolated and protected from inventory reuse.
- [x] Planned ownership boundaries crosswalked against Build 001, 002 and 008.
- [x] No inventory migration was found in the inspected repository tree.
- [ ] Development database relation/column inventory returned and reviewed.
- [ ] Existing manual objects, grants, policies, triggers and ownership reconciled with Git migration history.
- [ ] Reuse/extend/create decision approved for each actual database object.

## 7. Next stage

**Build 005.3 — Database schema discovery and reconciliation.** First obtain the read-only SQL outputs above. Then produce an object-by-object reconciliation and migration plan. Only after review should Build 005.4 define additive SQL migrations, constraints, indexes, RLS policies, grants, rollback strategy and tests. No production changes are authorized by this document.
