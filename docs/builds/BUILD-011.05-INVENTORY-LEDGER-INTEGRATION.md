# Master Build 011.05 — Inventory Ledger Integration

Status: **repository-level ledger integration specification committed; live schema verification and runtime implementation pending**.
Branch: `implementation/build-011-purchasing-receiving-integration`.
Date: 2026-11-07.

## Objective

Define one authoritative inventory ledger and balance projection for MME OS. Integrate approved receiving intake, POS sales, returns, transfers, reservations, adjustments and reconciliation without allowing multiple services to mutate stock independently.

Preserve existing 009.59 inventory-ledger work as source material. Do not deploy its current migration unchanged, create a parallel production ledger, or apply a migration until the live Supabase schema and canonical product/location/identity authorities are verified.

## Source review — Build 009.59

The migration defines:
- `mme_inventory_balances`, keyed by SKU reference, location code and currency.
- `mme_inventory_ledger`, an append-oriented movement table with an idempotency key, quantity/value delta, source and actor.
- `mme_inventory_cost_layers`.
- `mme_inventory_adjustment_requests`.
- `mme_inventory_reconciliation_runs`.
- `mme_inventory_audit`.
- A receiving intake posting function that updates ledger, balance, cost layer, intake status and audit.
- An adjustment request and independent-review posting flow.

This is useful design material, but it is not yet a proven production source of truth.

### Critical defects and gaps to resolve

1. **Noncanonical identity:** balance and ledger keys use SKU text and location code. The formal PO implementation uses product UUID and location UUID. The final ledger must reference the canonical product and location IDs and preserve SKU/code as immutable descriptive snapshots only.
2. **Caller-supplied actor:** receipt and adjustment functions accept actor UUIDs as parameters. The trusted server must derive actor identity from the authenticated MME session and verify active employee/person identity and permissions. Client-provided actor values must not be authoritative.
3. **Replay payload integrity:** when an intake is already posted, the function returns the existing entry by source intake without comparing the new command's canonical payload/fingerprint to the original. The same command key with altered data must fail with a conflict.
4. **Source uniqueness:** the ledger needs a unique constraint for the source event identity and movement purpose, not only a unique client idempotency key. One intake must not be posted twice under different keys.
5. **Receiving exception eligibility:** posting currently allows sessions in both `reconciled` and `exception` states. Only accepted, finalized and eligible quantities with all blocking discrepancies resolved or explicitly waived by an authorized reviewer may post.
6. **Serial integrity:** counting accepted serial records is insufficient. Validate exact accepted quantity, uniqueness across all devices/locations, no rejected/duplicate/extra identifiers, valid line ownership, and policy-required test/activation-lock state.
7. **Cost-layer semantics:** weighted-average balance valuation and cost-layer remaining quantities must reconcile for receipts, sales, returns, transfers, write-offs and reversals. The existing receipt path creates a cost layer but a complete issue/consumption/return policy is not proven by this migration.
8. **Cost allocation:** landed cost allocation needs documented allocation basis, currency consistency, precision, rounding and residual handling. Dividing a rounded total by accepted quantity can produce a per-unit rounding difference; preserve exact source totals and reconcile the residual.
9. **Currency segmentation:** separate balances per currency can imply separate quantities for the same product/location. Quantity-on-hand must have one canonical product/location balance; valuation must use the inventory functional currency with source-currency cost evidence and approved FX conversion. If MME explicitly adopts multi-currency inventory books, the accounting design must define how physical quantity is consolidated.
10. **Negative stock and reservation rules:** every decrement must lock the canonical balance, preserve reserved quantity and enforce policy on negative available stock. Reservations are commitments, not physical ledger quantity movements.
11. **Ledger immutability:** prevent update/delete/truncate for all application roles, including service role, with controlled database ownership and compensating reversal entries. Ensure privileged functions cannot mutate prior ledger events.
12. **Direct PO receiving conflict:** 010.41's PO receive function directly changes a separate balance and movement family. It must be retired/disabled from the active write path after a controlled cutover; no dual posting.
13. **RLS and function hardening:** validate grants, table ownership, fixed safe search_path, execute privileges, security-definer boundaries, policy behavior and audit access in a disposable database.
14. **Value sign conventions:** formally specify quantity and value delta signs for receipt, sale, return, adjustment, transfer, reservation and release. Reservations should not create physical stock quantity changes.
15. **Concurrent source posting:** lock the source intake/transaction and the canonical product/location balance in a consistent lock order. Verify race safety under simultaneous posts, sales, transfers and adjustments.

## Canonical ledger architecture

### Authority model

- **Inventory ledger:** immutable source of truth for physical stock movements and valuation events.
- **Inventory balance:** derived/maintained projection of the ledger, updated in the same database transaction as each posting.
- **Reservations:** separate commitment records that affect available-to-promise, not physical on-hand quantity.
- **Cost layers:** valuation evidence linked to ledger events; their consumption and remaining quantities must reconcile to the valuation method.
- **Serial registry:** unique device identity and lifecycle records linked to product and location; serial status must reconcile with physical quantities.
- **Reconciliation:** read-only comparison of ledger-derived quantities/value with balance projection, serial registry and external count evidence.

Do not permit the storefront, POS, receiving UI, warehouse UI or employee dashboard to update balance rows directly. All stock changes must call the same authorized inventory command/service.

### Canonical key

Each ledger event must reference:
- Canonical MME product ID.
- Canonical location ID.
- Movement type and quantity delta in the product's base unit.
- Value delta in the MME inventory functional currency.
- Original transaction currency, amount and FX evidence when applicable.
- Source entity type, source entity ID and source event/version.
- Unique idempotency command ID and canonical payload hash.
- Trusted actor/person ID, authorized role/scope and reason.
- Correlation ID, created timestamp and immutable evidence references.

SKU, manufacturer part number, supplier SKU, barcode and model are searchable identifiers/snapshots, not ledger primary identity.

## Movement semantics

| Event | On-hand quantity | Reserved quantity | Valuation behavior |
|---|---:|---:|---|
| Receipt accepted | Increase | No change | Add accepted receipt value and cost layer |
| POS sale fulfilled | Decrease | Release applicable reservation | Relieve inventory at approved valuation cost |
| Customer return accepted | Increase | No change | Restore cost under return policy; inspect/condition may quarantine |
| Transfer out | Decrease at source | No change | Transfer carrying value, not a new gain/loss |
| Transfer in | Increase at destination | No change | Preserve transferred carrying value and source transfer link |
| Positive adjustment | Increase | No change | Add approved evidence-backed value |
| Negative adjustment | Decrease | No change | Relieve carrying value and record reason/variance |
| Reservation created | No change | Increase | No ledger value movement |
| Reservation released | No change | Decrease | No ledger value movement |
| Reservation fulfilled | Decrease | Decrease | Sale/fulfillment posting relieves value once |
| Reversal | Compensating delta | As applicable | Reverse prior event by reference; never edit original row |

A reservation is not a receipt or a sale. A transfer is two linked legs under one atomic transfer command. A reversal is a new compensating event and must reference the original event.

## Valuation policy

The recommended default for ordinary MME inventory is **perpetual weighted-average cost**, subject to Finance approval and accounting policy. Do not silently switch valuation method for existing stock.

For a receipt:
- New quantity = old on-hand + accepted receipt quantity.
- New inventory value = old carrying value + accepted receipt value in functional currency.
- New weighted average = new inventory value / new on-hand quantity, using approved precision.

For an issue:
- Relieve quantity at the current approved average cost at the transaction's locked balance version.
- Reduce carrying value by the relieved quantity times average cost, with a defined rounding/residual policy.
- Do not let an issue create negative on-hand or negative inventory value unless an explicitly approved backorder/negative-stock policy applies.

For returns:
- Link to original sale where available and restore original carrying cost according to approved return accounting policy.
- Unmatched returns require a controlled valuation decision and must not default to zero-cost stock.
- Returned goods may enter quarantine pending inspection; quarantine is excluded from available-to-promise.

For transfers:
- Source and destination legs use the same product, quantity and carrying value.
- Both legs post atomically under one transfer ID.
- Transfer does not create profit/loss merely because location changes.

For landed cost:
- Store original component evidence (freight, duty, insurance, handling, rebates/credits) and currency.
- Define allocation basis by policy (quantity, value, weight, volume or specific assignment).
- Convert currency using a sourced, timestamped, approved FX rate.
- Preserve unrounded source inputs; allocate rounding residual deterministically so the total allocated amount equals the source total exactly.

Cost-layer records may remain for traceability, but if weighted-average is the authoritative valuation method they must not be treated as a second independent FIFO valuation authority.

## Balance and availability model

For each canonical product/location:
- `on_hand` = physical accepted stock posted to ledger, including quarantine if represented in a separate stock status bucket.
- `reserved` = open, valid commitments.
- `quarantined` = physically present but not sellable/available.
- `available_to_promise` = eligible on-hand minus reservations and quarantine, subject to policy.
- `in_transit` = stock dispatched from a source location but not yet accepted at destination; not destination on-hand.

The implementation should decide whether status buckets live in the balance projection or separate stock-status records. Do not conflate physical on-hand, available quantity and reserved quantity.

## Idempotency and atomic posting

Every command must:
1. Resolve the authenticated actor and permissions server-side.
2. Validate source entity, source version and requested transition.
3. Build a canonical payload fingerprint from product, location, quantity, value, currency/FX evidence, source event and command type.
4. Insert or lock the idempotency command record.
5. If the same key and same fingerprint already completed, return the exact prior result.
6. If the same key has a different fingerprint, reject with a conflict.
7. Enforce unique source-event posting so a new key cannot post the same receipt/sale/transfer leg twice.
8. Lock source and balance rows in a deterministic order.
9. Validate stock, reservations, serials, cost and policy invariants.
10. Insert immutable ledger event(s), update balance projection and cost/serial/commitment projections, and append audit/outbox event in one transaction.
11. Commit all effects or roll them all back.

The system must support safe retry after timeouts without double posting.

## Adjustments and reconciliation

- Adjustment requests require reason code, detailed explanation, evidence and requester identity.
- Independent approval is required according to value/risk threshold; no self-approval.
- Adjustment approval and ledger posting are one atomic transaction.
- Cycle counts create count sessions and variances; they do not directly overwrite balance.
- Reconciliation compares ledger-derived quantity/value with the balance projection and records matched/variance status.
- A variance creates a review case; it does not automatically post an adjustment.
- Serial-level counts must reconcile with tracked-unit quantities.
- Corrections use compensating ledger events and preserve the original transaction.

## Required service boundary (logical; not yet implemented)

- `POST /api/inventory/commands/receipts` — post accepted receiving intake.
- `POST /api/inventory/commands/sales` — post fulfilled POS sale.
- `POST /api/inventory/commands/returns` — post inspected customer return.
- `POST /api/inventory/commands/transfers` — atomic source/destination transfer.
- `POST /api/inventory/commands/reservations` — reserve or release stock commitment.
- `POST /api/inventory/commands/adjustments` — submit/approve/post adjustments under policy.
- `GET /api/inventory/balances` — permission-scoped stock and availability projection.
- `GET /api/inventory/ledger` — filtered immutable movement history.
- `GET /api/inventory/reconciliation` — variance and reconciliation status.
- `GET /api/inventory/serials/:id` — protected device identity and lifecycle status.

These routes describe a proposed service boundary only; they are not claimed to exist or be deployed.

## Security and audit requirements

- All write commands resolve active MME identity, role and location scope server-side.
- No client-supplied actor UUID or role string can authorize a stock movement.
- Separate receive, inspect, post, adjust, approve-adjustment, transfer, reserve, release and reconcile permissions.
- Ledger and audit history are append-only to application roles.
- Sensitive serial/IMEI values are protected at rest and masked in ordinary UI, logs, notifications and analytics.
- Restrict ledger reads by business need; broad customer-facing APIs must not expose cost or internal movement notes.
- Security-definer functions have a fixed safe search_path, minimum grants and explicit ownership.
- RLS and service-role behavior must be verified against actual MME roles.
- Every stock movement records source, reason, actor, timestamp and correlation ID.

## Mandatory tests

### Ledger correctness
- Receipt adds exactly accepted quantity and value once.
- Same idempotency key/same payload returns same ledger result.
- Same idempotency key/different payload conflicts.
- Different idempotency keys cannot post the same source event twice.
- Two concurrent receipts for same product/location serialize correctly.
- Sale cannot exceed available quantity or violate reservation rules.
- Return references original sale or enters controlled unmatched-return workflow.
- Transfer source and destination legs commit together or neither commits.
- Transfer preserves quantity and carrying value.
- Reservations do not change physical on-hand or inventory value.
- Adjustment requires independent approval and cannot reduce stock below reserved quantity.
- Reversal is a new event and original ledger row remains unchanged.

### Valuation correctness
- Weighted-average cost reconciles after multiple receipts and issues.
- Rounding residuals are deterministic and total value reconciles.
- Landed cost allocation totals equal source evidence totals.
- FX conversion stores rate, source, timestamp and original amount.
- Negative stock/value is blocked unless explicit approved policy permits it.
- Cost layer quantities reconcile to the chosen valuation method.

### Identity and serial integrity
- Product/location IDs must be canonical and active.
- Duplicate serial/IMEI across receiving, inventory, sales and returns is rejected.
- Serial registry count reconciles to tracked on-hand by status/location.
- Quarantine is excluded from sellable availability.
- Actor spoofing, inactive user and wrong-location writes are denied.

### Security and regression
- RLS, grants, function ownership/search_path and audit immutability pass.
- POS sale, customer return, receiving, warehouse transfer, storefront availability and purchasing regressions pass.
- Migration replay and rollback are tested on a disposable Supabase database.

## Cutover plan and production safeguards

1. Obtain the live read-only Supabase schema/migration audit.
2. Identify canonical product, location, identity, stock balance, movement, reservation, serial and cost structures.
3. Profile row counts, duplicate keys, orphan references and ledger/balance differences without exposing PII.
4. Select exactly one existing ledger authority; if a live ledger already serves POS/warehouse, preserve it and adapt receiving to it.
5. Create a source-event and SKU/location-to-product/location crosswalk with unresolved records quarantined for review.
6. Define valuation policy with Finance and reconcile opening inventory quantity/value before cutover.
7. Disable alternate stock mutation paths only after all callers are migrated and a rollback plan exists.
8. Replay additive migration on disposable Supabase; test concurrent operations, RLS, idempotency, valuation and rollback.
9. Run a shadow reconciliation before switching all stock commands.
10. Obtain explicit release approval before production migration, merge or Vercel promotion.

Do not change Vercel cron frequency or upgrade the Vercel plan as part of this build. Do not trigger a production deployment for documentation-only changes.

## Acceptance checklist

- [x] 009.59 ledger/balance/cost/adjustment implementation inspected.
- [x] 010.41 competing direct PO stock mutation identified.
- [x] Canonical product/location ledger authority defined.
- [x] Movement, reservation, transfer and reversal semantics defined.
- [x] Weighted-average valuation and landed-cost controls defined.
- [x] Idempotency, source uniqueness and atomicity requirements defined.
- [x] Security, serial and reconciliation tests specified.
- [ ] Live Supabase schema and migration history verified.
- [ ] Existing live stock authority selected.
- [ ] Opening stock and valuation reconciled.
- [ ] Canonical ledger integration implemented.
- [ ] Disposable database, security, concurrency and end-to-end tests passed.
- [ ] Production cutover approved and verified.

## Completion status

Build 011.05's repository-level inventory ledger integration design is documented. This does not mean a live inventory ledger has been implemented, migrated or deployed. No database mutation, branch merge or production deployment is performed by this document.
