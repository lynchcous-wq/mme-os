# Build 009.38 — Native Inventory & Cost of Goods Sold Financial Adapter

Status: implementation committed to a review branch. Automated contract tests, TypeScript validation, fresh Supabase migration replay, and end-to-end inventory/COGS tests are pending CI.

## Objective
Connect Build 001 inventory receipt costs, inventory balances, serialized unit costs and POS sale finalization to Build 009.32 financial reporting. Actual acquisition cost and approved landed-cost components are the source of COGS. Retail price, equal-per-pallet cost allocation and guessed estimates are prohibited.

## Delivered
- `supabase/migrations/20261105001180_build009_native_inventory_cogs_adapter.sql`
- Additive receipt cost-component and allocation ledgers.
- Two-person approval for landed-cost allocation, with store-scoped permission checks.
- Serialized inventory receiving with per-unit cost and serial/IMEI digests plus last-four display values; raw serial/IMEI values are not persisted by this migration.
- Serialized unit reservation against a single order line through a service-only RPC and authenticated API endpoint `app/api/pos/inventory/serialized/assign/route.ts`.
- Finalized POS sale trigger that consumes active inventory reservations, writes immutable per-line COGS snapshots, and records inventory sale movements.
- Native POS financial export now imports one negative `cost_of_goods_sold` fact per COGS snapshot using a stable transaction/order-line source reference.
- Store-scoped COGS snapshot visibility in `app/internal/financial-connectors`.
- Contract suite `tests/build009-native-inventory-cogs-adapter.test.mjs` and command `npm run test:build009:inventory-cogs`.
- CI workflow `.github/workflows/build009-native-inventory-cogs.yml`.

## Cost model
- Non-serialized products use the existing inventory balance `average_unit_cost_cents` (weighted-average method).
- Serialized products use the actual unit acquisition cost from the matched serial-unit ledger.
- Additional freight, shipping, auction fees, customs, refurbishment, insurance and other approved receipt costs can be allocated by extended receipt cost or quantity.
- Allocation rounding remainder is assigned deterministically to the final receipt line.
- Landed cost must be recorded before subsequent stock movements; historical sold cost snapshots are never silently rewritten.
- A cost snapshot is written exactly once per POS transaction/order line.
- COGS is exported as a negative financial fact. Existing report aggregation already includes `cost_of_goods_sold_minor` and gross-profit calculations.

## Serialized inventory boundary
Serialized intake and order-line assignment are implemented at the data/API layer. The existing Build 001 standard order-creation function explicitly excludes serialized products; this build does not claim that the complete customer serialized checkout flow has been enabled. Until that checkout path is updated and end-to-end tested, serialized items must not be offered for normal checkout merely because a unit can be received or assigned through the internal API.

## Security and integrity
- New tables enable RLS and revoke direct anon/authenticated access.
- Privileged RPCs are service-role-only; actor and approver identities are resolved from authenticated server context for the API, then checked against active identity, employment, permission, store scope and freeze state in the authorization function.
- Landed-cost approval requires two distinct identities.
- Serial/IMEI values are normalized, hashed and represented in records only by digest and last-four fields; raw values are not stored. This is data minimization, not a substitute for a separately managed keyed-tokenization scheme if threat modeling requires one.
- POS finalization and inventory consumption occur in the same database transaction. If reservation, serial matching or cost snapshot validation fails, finalization rolls back rather than recording a sale without corresponding inventory consumption.
- No historical movement or already-snapshotted COGS is silently rewritten.
- No PAN, CVV, PIN or payment credentials are collected or stored.

## Validation
CI runs:
- `npm run lint`
- `npm run test:build009:inventory-cogs`
- `npm run test:build009:native-financial`
- `npm run test:build009:financial-provider-sync`
- `supabase db reset --local`
- `supabase test db --local`
- `supabase db lint --local`

Required end-to-end cases include weighted-average receipt costing, separate landed-cost components, rounding remainder, two-person approval, cross-store permission denial, duplicate component reference, serialized serial/IMEI duplicate rejection, serial reservation and release, finalized sale consumption, missing serial rejection, duplicate export, COGS/report totals, and closed-period handling.

## Rollout boundary
This is a draft implementation branch based on Build 009.37. No production migration, live inventory consumption, serial checkout enablement, accounting-period close, or website deployment is claimed. Merge and apply only after review and successful fresh-database validation.
