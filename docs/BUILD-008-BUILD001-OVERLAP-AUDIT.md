# Build 008 — Build 001 Inventory and Commerce Overlap Audit

**Review branch:** `build-008-inventory-foundation`  
**Inspected implementation branch:** `integration/build001-catalog-inventory`  
**Review type:** Read-only repository inspection of migration and test inventory  
**Decision:** Build 008 must extend the existing Build 001 inventory domain. Do not create parallel product, stock, reservation, serialized-unit, receiving, landed-cost or disposition ledgers.

## 1. Confirmed existing implementation assets

The inspected Build 001 integration branch contains catalog APIs, employee inspection APIs, a substantial set of inventory migrations, and corresponding pgTAP files. These are repository artifacts; this audit does not independently certify their production deployment or runtime configuration.

| Capability | Existing evidence | Build 008 consequence |
|---|---|---|
| Product catalog | `app/api/catalog/route.ts`, `app/api/catalog/[id]/route.ts`, `app/api/catalog/[id]/units/route.ts`; catalog foundation/correction/authorization migrations and tests | Reuse product IDs, catalog lifecycle and unit linkage. Do not create a second product catalog. |
| Aggregate stock balances and movement ledger | `20261103001000_build001_receiving_adjustments_transfers.sql` defines receipt and movement records and receive/adjust/transfer RPCs; tests include receiving adjustments/transfers | Extend the existing stock owner and movement semantics only after reviewing all functions, grants and tests. |
| Order reservation/payment lifecycle | `20261103000700_build001_reservation_lifecycle.sql` contains reservation release, expiry and verified-payment event RPCs; tests include reservation lifecycle and unified expiry | Reuse order reservation lifecycle; do not create a competing order hold/commit model. |
| Serialized physical units | `20261103000800_build001_serialized_units.sql` defines `mme_serialized_units` with product/location, serial, optional IMEI, condition and unit status; `20261103000900` serialized checkout and related tests | Reuse the existing unit identity. Review encryption/masking and identifier access before expanding it. |
| Serialized unit transfers and disposition | `20261103002800` serialized unit transfers; `20261103008200` serialized-unit disposition ledger; `20261103008300` immutable disposition ledger | Build 008 must preserve existing disposition history and compensating/immutable controls. |
| Receiving, adjustment, transfers | `20261103001000` plus `20261103004500` multilocation transfer approval, `20261103005600` receiving reconciliation, `20261103005700` serialized PO receiving reconciliation | Extend these workflows; first map actual state transitions, authorization and reconciliation behavior. |
| Inspection, repair, quarantine, evidence | `20261103001100` inspection/damage/repair/quarantine; `20261103007700` device test checklist; `20261103007800` photo evidence; `20261103007900` employee permissions; `20261103008000` atomic inspection submission; `20261103008100` private evidence bucket; associated API routes and tests | Do not create a separate inspection engine. Verify Build 017 contract and current Build 004 dual authorization before extending routes. |
| Landed cost | `20261103002200_build001_landed_cost_allocation.sql` defines cost pools and per-line allocations; RPC supports `extended_acquisition_value` and `equal_per_unit` | Build 008 spec's weight/volume/other allocation options are not evidenced in this migration. Treat them as a gap requiring accounting approval, not as implemented. |
| Cross-channel claims | `20261103005900_build001_cross_channel_inventory_claims.sql` defines claims and lines for customer holds, POS quotes, subscriptions, auctions and manual allocations; serialized and aggregate stock are locked/claimed through RPCs | Reuse the cross-channel claim service for supported use cases; verify idempotency, expiry and ownership contracts before adding channels. |
| POS/payment inventory consumption | `20261103003300_build001_pos_payment_inventory_consumption.sql`, mixed-cart/payment migrations and tests | Preserve payment authority and existing inventory consumption transaction boundaries. |
| Website/fulfillment | shipping/pickup fulfillment, customer notifications, worker reliability, checkout recovery and cross-channel claim migrations/tests | Verify actual publication/provider integration; no website/Wix deployment is inferred from schema artifacts. |
| Inventory analytics | control center KPIs, reorder intelligence, forecasting, exception management, financial intelligence, executive snapshot, shrinkage, sales velocity/stock cover and transfer recommendation migrations/tests | Reuse governed projections; confirm formulas, source freshness and actual-vs-estimated labeling before adding reports. |

## 2. Important verified schema limitations and design deltas

### 2.1 Serialized identifier protection
The inspected serialized-unit migration stores `serial_number` and optional `imei` as text columns and enforces format/uniqueness constraints. That migration alone does not demonstrate encryption-at-rest at the column/application layer, purpose-limited access, masking, restricted bulk export, or retention policy. Build 008 must not expose these fields in public catalog APIs or ordinary logs. Verify the complete access path and storage controls before declaring the Build 008 identifier-vault requirement satisfied.

### 2.2 Landed-cost allocation methods
The inspected landed-cost migration accepts only `extended_acquisition_value` and `equal_per_unit`. Build 008's additional weight, volume and documented alternative methods are not supported by this verified contract. The existing weighted/value-based method must not be replaced or silently reinterpreted. A new method requires a reviewed migration, source measurements, rounding/residual handling, immutable method version and accounting/CEO approval.

### 2.3 Two stock models already exist
The repository includes aggregate `mme_inventory_balances` and serialized `mme_serialized_units`, plus shared cross-channel claims. Build 008 must specify when each product uses aggregate quantity versus per-unit identity, and how reservations/claims prevent double-counting across both models. Never sum aggregate and serialized quantities as if they were independent stock.

### 2.4 Existing states are narrower than the Build 008 vocabulary
The serialized-unit migration uses constrained unit states and a later disposition migration adds terminal outcomes. The aggregate inventory, listing, receiving, inspection and reservation state machines are distributed across multiple migrations. Build 008's proposed unified status list is not proof of one existing canonical state machine. Preserve domain-specific states and map them explicitly; do not collapse listing, physical stock, reservation, payment and fulfillment states.

### 2.5 Existing tests are not equivalent to complete operational validation
The integration branch includes pgTAP suites for many of the capabilities above. Their existence is not proof of physical scanner/printer compatibility, production provider connectivity, all concurrency edge cases, or Build 017 compatibility. Run the actual CI and sandbox tests on the selected implementation base before release.

## 3. Proposed ownership map

- **Catalog:** owns product identity, model attributes, product version and public catalog content.
- **Inventory:** owns physical unit/balance state, locations, movement history, receiving, transfers, reservation/claim effects and inventory disposition.
- **Orders/POS/Payments:** own order and payment state; inventory consumes only verified, idempotent commands/events.
- **Acquisition/COGS/Accounting:** own source acquisition records, cost pools, approved cost allocation and valuation policy; inventory references the approved cost result.
- **Pricing:** owns approved active selling price and markdown policy; inventory must not independently set price.
- **Returns/Build 017:** owns return eligibility, inspection decision and authorized disposition request; inventory applies only a verified disposition event.
- **Identity Matrix:** owns actor identity and employee action/location scope; inventory routes enforce server-side authorization.
- **Build 006:** owns durable tasks, notification and workflow lifecycle for inventory exceptions.
- **BI/Build 005:** owns governed read projections; no analytics endpoint is a stock mutation path.

## 4. Next engineering gates

1. Complete Build 004 integration and approve the canonical permission-evaluation contract; keep legacy checks until an explicit reviewed cutover.
2. Complete Build 007 CRM schema/API and identity integration sufficiently to define customer relationship references, customer-held stock/quote ownership, and assignment provenance.
3. Produce a detailed table/RPC/API crosswalk for every Build 001 inventory migration and route; record grants, RLS, caller roles, idempotency, lock ordering and test coverage.
4. Resolve the aggregate-versus-serialized stock contract and the cross-channel claim/checkout conversion transaction boundary.
5. Approve identifier protection and landed-cost method expansion with Security and Accounting.
6. Verify Build 017 and provider/hardware contracts before implementing returns, website, POS, shipping or label integrations.
7. Only after the above, design additive Build 008 migrations and API/UI changes against the approved existing owners.

**Current result:** The Build 001 implementation already covers a substantial portion of the Build 008 specification. The safe Build 008 path is a controlled extension and integration program, not a greenfield inventory rebuild. No Build 008 runtime code or production change is made by this audit.
