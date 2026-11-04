# Build 005.4 — Inventory Core Implementation Blueprint

**Company:** Much More Electronics  
**Build:** 005 — Inventory Core  
**Stage:** 005.4 — Logical model, lifecycle, service contracts and implementation sequence  
**Status:** Design specification only; no SQL migration or application implementation  
**Branch:** `implementation/build-005-inventory-core`  
**Depends on:** Build 001 architecture; Build 004 identity and authorization foundation; Build 005.1 architecture; Build 005.2 schema crosswalk and supplied development discovery results

## 1. Purpose and status

This stage converts the approved inventory architecture into an implementation-ready logical blueprint. It does not claim the remaining database security preflight is complete. It does not create or alter database objects, install dependencies, change application routes, or deploy code.

The user has paused further database inspections. Respect that pause. Continue design work without requesting or running additional inspection queries. Before a migration is authored or applied, resume the required security/migration preflight and review its results.

## 2. Authority boundaries

| Domain | Authoritative responsibility | Inventory Core interaction |
|---|---|---|
| Identity / Build 004 | Person identity, customer/employee relationship, roles, grants and server authorization | Accept only trusted actor context established by server-side authorization; never store roles or permissions as client assertions |
| Catalog | Product family, brand/model, public descriptions, technical specifications and media references | Link sellable variants to catalog products; inventory does not own public copy |
| Inventory Core | Physical units, quantity lots, locations, movements, holds, reservations and stock availability | Sole authority for stock mutations and availability |
| Acquisition / COGS | Supplier/pallet purchase evidence, fees, freight and approved cost allocation | Consume item/lot cost evidence or approved cost snapshots; do not equal-split unrelated items |
| Pricing | Approved list/sale prices, markdown rules and price history | Consume approved price versions; do not calculate or publish prices as an authority |
| Orders / POS / Website / Auction | Cart/order, tender/payment state, customer channel and sale intent | Request reserve, commit, release and fulfillment transitions through inventory service |
| Returns / Build 017 | Return authorization, refund decision, inspection and disposition recommendation | Receive an authorized disposition command; returned stock remains unavailable until inspection and release |
| Shipping / Pickup | Shipment, handoff, delivery and pickup completion | Request allocation and record controlled location handoffs; cannot directly edit balances |
| Analytics | Reporting and projections | Read events/read models; never mutate authoritative inventory |

## 3. Logical entity catalogue

These are logical concepts, not approved physical table names. During later schema design, reuse or extend an equivalent existing Build 001 object if one is identified. Never create a duplicate source of truth.

| Logical entity | Minimum responsibility | Key relationships |
|---|---|---|
| Catalog product reference | Stable product family/model reference | Referenced by one or more sellable SKUs |
| Sellable SKU | MME sellable configuration, condition policy and stable SKU code | Belongs to a catalog product; referenced by stock units/lots and channel offers |
| Inventory location | Configured physical or virtual stock location and allowed capabilities | Source/destination of movements; scope boundary for permissions |
| Inventory unit | Individually tracked physical item | SKU, location, acquisition line, condition and identifiers |
| Inventory quantity lot | Quantity-tracked non-serialized stock | SKU, location and movement ledger |
| Acquisition receipt / receipt line reference | Traceable purchase, pallet, vendor shipment and item-specific allocation evidence | Links source documents and received units/lots |
| Unit identifier | Typed serial, IMEI or other identifier | Belongs to an inventory unit; sensitive access controlled and audited |
| Condition assessment | Grade and inspection evidence, distinct from lifecycle status | Belongs to a unit or applicable lot; records test version and inspector |
| Stock movement | Immutable record of a stock-changing event | SKU/unit/lot, quantity, source/destination, actor and business reference |
| Reservation | Time-bounded hold on a unit or quantity | References channel/order/cart and reserved stock |
| Inventory hold | Non-saleable block for inspection, damage, loss investigation or other reason | Applies to unit/lot/quantity and location |
| Availability projection | Rebuildable channel/location/SKU view derived from ledger and active reservations/holds | Read model only; not an independent writable stock count |
| Outbox event | Reliable publication record for committed inventory changes | Created atomically with the authoritative transaction |

## 4. SKU and physical identity rules

- SKU codes are stable MME business identifiers, unique within the defined MME namespace, and not generated from mutable product titles.
- A catalog product may have multiple SKUs when sellable configuration, included accessories, condition, bundle, or fulfillment behavior materially differs.
- A serial number or IMEI identifies a physical unit, never a SKU.
- Serialized devices use one-unit records and controlled identifier capture.
- Non-serialized accessories may use quantity lots; each movement must preserve quantity and location history.
- A unit must not be simultaneously represented as both independently serialized stock and an untracked quantity balance.
- Identifier normalization, uniqueness scope and exception handling must be finalized in physical schema design. Raw values remain protected; ordinary UI/logs show masked values.
- A product listing with no received/available stock may be displayed as coming soon, but cannot be reserved or checked out unless an explicit approved preorder policy exists.

## 5. Inventory lifecycle and transition policy

Lifecycle state and physical location are separate dimensions. A unit can be physically in a receiving area while its lifecycle is inspection-pending; changing its status must not silently rewrite its location.

Initial proposed transition policy:

| Current state | Allowed next state | Required evidence / guard |
|---|---|---|
| expected | received | Receipt reference and receiving actor |
| received | inspection_pending | Receiving confirmation |
| inspection_pending | available | Required inspection completed and passed or approved grade/disposition |
| inspection_pending | quarantined | Failed, incomplete or disputed inspection with reason |
| available | reserved | Atomic reservation transaction |
| reserved | available | Reservation released, cancelled or expired through controlled operation |
| reserved | sold | Authorized order commit; inventory commit is idempotent |
| available | display | Authorized display assignment and location movement |
| display | available | Display release and condition check |
| available / display | quarantined | Authorized hold with reason |
| quarantined | inspection_pending | Reinspection authorized |
| quarantined | available | Explicit release approval and required evidence |
| sold | fulfilled | Order/fulfillment confirmation; preserve sale and handoff references |
| fulfilled | returned_pending_inspection | Authorized return receipt; never auto-restock |
| returned_pending_inspection | returned_available | Return inspection and approved disposition |
| returned_pending_inspection | returned_quarantined | Defect, missing component, fraud review or unresolved test |
| available | transferred | Transfer workflow; source/destination movement pair or equivalent atomic transfer |
| any applicable stock state | lost / damaged / disposed | Privileged reason-coded adjustment and evidence |

The complete transition graph, allowed actors, reversals and edge cases must be approved before implementation. Invalid transitions fail closed. Historical movements are never rewritten; corrections use compensating events.

## 6. Movement ledger contract

Every stock-changing operation produces a durable movement record with, at minimum:

- Stable movement ID and event/idempotency key.
- Movement type and reason code.
- SKU and either inventory-unit ID or quantity-lot ID.
- Positive quantity in a defined unit of measure; direction is represented by movement type/source/destination rather than ambiguous signed values.
- Source and destination location where applicable.
- Trusted actor/service identity, timestamp and authorization context reference.
- Related receipt, order, return, transfer, inspection or adjustment reference.
- Optional notes/evidence references with access controls.
- Correlation ID for tracing a multi-step business operation.

Movement records are append-only for application runtime roles. A transfer must be atomic from the inventory authority's perspective. A failed operation must not leave only one side of a transfer posted. Replaying the same idempotency key must return the prior outcome or a safe equivalent, never duplicate stock.

## 7. Reservation and availability contract

Reservation operation accepts:
- SKU and requested quantity or explicit unit IDs.
- Channel and stable cart/order reference.
- Requested location/fulfillment mode.
- Expiry policy selected by server-side configuration.
- Idempotency key.

The inventory service validates available-to-sell, scope, location eligibility and reservation policy inside a concurrency-safe transaction. For serialized stock, it locks/selects eligible units so the same unit cannot be reserved twice. For quantity stock, it atomically ensures the remaining allocatable quantity is sufficient.

Reservation statuses: pending, active, committed, released, expired, cancelled, failed. Exact status transitions are server-controlled. Expiry processing must be repeatable and observable; an expired hold is released once. A reservation does not equal a paid order, and a payment does not by itself authorize an inventory commit.

Availability is derived from posted movements, active holds, active reservations, location eligibility and channel rules. Cached projections may be stale and must include a freshness marker. Checkout must validate against the authoritative inventory service, not trust a browser cache.

## 8. Service/API command boundaries

Proposed internal server-side command contracts (names illustrative; no endpoints are implemented here):

- `catalog.resolveSku(skuId | skuCode)` — resolve sellable SKU and catalog reference.
- `inventory.receive(receiptReference, lines, idempotencyKey)` — record accepted receiving quantities/units into receiving or inspection location.
- `inventory.completeInspection(unitId, assessment, disposition, reason)` — store inspection outcome and request an allowed state transition.
- `inventory.reserve(request, idempotencyKey)` — atomically hold stock.
- `inventory.releaseReservation(reservationId, reason, idempotencyKey)` — release an active reservation once.
- `inventory.commitReservation(reservationId, orderReference, idempotencyKey)` — commit stock after trusted order orchestration authorizes the sale.
- `inventory.transfer(stockReference, fromLocation, toLocation, quantity, idempotencyKey)` — atomically move stock.
- `inventory.adjust(stockReference, delta, reasonCode, evidence, idempotencyKey)` — privileged, reason-coded compensating adjustment.
- `inventory.getAvailability(skuId, location/fulfillment scope, channel)` — return availability and projection freshness.
- `inventory.reconcile(scope)` — privileged/read-only reconciliation report.

All commands authenticate the server actor, enforce Build 004 permission and resource/location scope, validate state transitions, use idempotency, and write audit/outbox records transactionally. No public client receives direct write access to inventory tables. Browser input may express intent but cannot set trusted actor, cost, price, final availability, stock status or permission scope.

## 9. Cost and price handling

- Acquisition cost, landed cost, approved retail price, sale price, tax and margin remain distinct.
- Inventory receives cost evidence or an approved cost snapshot from Acquisition/COGS, not an editable client-submitted cost.
- Allocation method must be explicit and reproducible (for example item-specific valuation, weight, volume, or another approved driver); do not default to equal allocation across unlike electronics.
- Keep the allocation inputs, source document, method/version, rounding and approval reference.
- Pricing is a separate authority. Every displayed price should resolve to an approved price version for the channel and time.
- Margin reporting must identify its cost basis and exclude sales tax from revenue where applicable.

## 10. Events and projections

Initial event vocabulary:
- `inventory.received`
- `inventory.inspection.completed`
- `inventory.unit.available`
- `inventory.reservation.created`
- `inventory.reservation.released`
- `inventory.reservation.expired`
- `inventory.reservation.committed`
- `inventory.stock.transferred`
- `inventory.stock.adjusted`
- `inventory.hold.placed`
- `inventory.hold.released`
- `inventory.return.received`
- `inventory.disposition.completed`

Each event carries event ID, schema version, occurred-at time, correlation ID, aggregate reference, and minimal necessary payload. Do not include full IMEI/serial, payment secrets, or unnecessary customer PII. Publish from a transactional outbox after commit; consumers deduplicate by event ID. Website, POS, auction and analytics projections can be rebuilt from authoritative state/events.

## 11. Permissions and audit model

Proposed permission keys for later mapping to Build 004 grants (not yet inserted into the database):

- `inventory.catalog.read`
- `inventory.catalog.manage`
- `inventory.receive`
- `inventory.inspect`
- `inventory.reserve`
- `inventory.commit`
- `inventory.transfer`
- `inventory.adjust`
- `inventory.cost.read`
- `inventory.identifier.read_sensitive`
- `inventory.identifier.update_sensitive`
- `inventory.hold.manage`
- `inventory.reconcile.read`
- `inventory.admin`

Permission is evaluated server-side against actor, resource, action, location and any applicable department/store scope. Cost visibility and full identifier access are separate permissions. High-impact actions require reason codes and audit evidence. Build 004 tables remain untouched by this blueprint; later permission-key registration must follow its established migration and governance process.

## 12. Implementation sequence after preflight resumes

1. Complete the paused security/migration preflight and reconcile the actual schema, constraints, indexes, RLS, grants, triggers and migration history.
2. Confirm the existing Build 001 schema and application source-of-truth mapping. If equivalent objects exist, extend them rather than creating duplicates.
3. Review and approve the physical entity names, constraints, indexes, foreign keys, RLS policies, grants and transition graph.
4. Author a development-only additive migration with explicit preconditions, transactional behavior where supported, recovery/rollback notes and migration ledger entry.
5. Add server-side inventory service and Build 004 authorization integration. Do not expose direct client writes.
6. Add automated tests for SKU/identifier uniqueness, serialized and quantity stock, reservation concurrency, idempotent replay, transfer atomicity, compensating adjustments, return disposition, variable landed-cost allocation, permission/location boundaries and event replay.
7. Run typecheck, lint, build, tests and dependency/security checks in the approved development workflow. Record actual command output and failures.
8. Only after explicit review, consider website/POS/auction/returns/shipping integration. Production deployment requires separate explicit authorization.

## 13. Acceptance criteria

Build 005 core is not complete until:
- One authoritative stock ledger controls all channels.
- Serialized units and non-serialized quantity lots cannot double-count the same stock.
- Every posted movement is attributable, reason-coded and idempotent.
- Reservations prevent overselling under concurrency.
- Sale, payment, return and fulfillment states remain separate but coordinated.
- Locations, holds and condition assessments are distinct and enforced.
- Cost and price authorities remain separate, with item-specific landed-cost support.
- Sensitive identifiers and cost data are protected by server-side scope.
- Events/projections are replayable and reconcile to authoritative inventory.
- Tests and build checks have actually run and their results are recorded.
- Existing identity objects remain unchanged.

## 14. Explicit non-actions

This blueprint creates no tables, migrations, policies, grants, indexes, application code, UI, payment behavior, live channel integration or production changes. The user has paused further database inspections; do not run additional inspection SQL unless the user later authorizes resuming that work.
