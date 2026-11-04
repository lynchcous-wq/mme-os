# Build 005.6 — API, Service Contract, and Test Matrix

**Status:** Design contract only  
**Branch:** `implementation/build-005-inventory-core`  
**Scope:** Proposed server-side Inventory Core interfaces and verification plan. No application code, dependencies, SQL, or database changes.

## 1. Purpose

Define how storefront, POS, auction, receiving, returns, shipping/pickup, and analytics request inventory operations without becoming independent authorities over stock state.

This contract depends on the Build 004 identity foundation and the Build 005 inventory architecture. It does not claim that the application-side authentication/session integration or inventory services are implemented.

## 2. Service boundary

All inventory mutations pass through a trusted server-side Inventory Core service. Client applications may request an operation, but may not dictate trusted values.

**Callers**
- Storefront and customer account: read sellable availability; request cart/order reservation.
- POS: resolve SKU; reserve and commit sale allocations.
- Receiving: record receipt, create stock, submit inspection results.
- Auction: reserve and commit auction allocations through the owning order workflow.
- Returns (Build 017): submit an approved return disposition that Inventory Core translates into a controlled stock transition.
- Shipping/pickup: query allocated units and record authorized handoff/dispatch transitions.
- Analytics: consume approved events/read models; no direct stock mutation.

**Authority**
- Build 004 resolves the authenticated person and active employee/customer relationships.
- Server-side authorization resolves permissions for the requested operation and target location.
- Inventory Core owns inventory lifecycle, stock movement, reservation state, and availability.
- Catalog owns product descriptions and catalog attributes.
- Pricing owns price decisions; Inventory Core does not accept a client-supplied price as an inventory fact.
- Acquisition/COGS owns landed-cost calculations and cost adjustments.
- Orders/POS owns the commercial transaction; Inventory Core owns the stock allocation and stock transition.
- Build 017 owns return/refund decision workflow; Inventory Core applies only an authorized disposition command.

## 3. Trust rules

Never trust client-supplied:
- actor/person/employee ID as proof of identity or permission;
- role, permission, employment status, or store access;
- current stock, available quantity, or unit lifecycle state;
- cost, retail price, markdown, or margin;
- authoritative source/destination location;
- reservation ownership or order payment status;
- an assertion that a sale, return, shipment, or pickup is complete.

The service derives the actor from the verified server session, checks authorization, loads authoritative records, and validates state transitions. Client-provided correlation IDs and idempotency keys are inputs for deduplication, not authorization.

## 4. Illustrative request and response shapes

The TypeScript-like shapes below are conceptual. They are not implemented interfaces or committed application code.

```ts
type ActorContext = {
  personId: string;       // resolved server-side from Build 004
  permissionSet: string[]; // resolved server-side; never accepted from client
  authorizedLocationIds: string[];
};

type CommandMeta = {
  idempotencyKey: string;
  correlationId?: string;
  expectedVersion?: number;
};

type InventoryResult<T> =
  | { ok: true; data: T; requestId: string }
  | { ok: false; error: InventoryError; requestId: string };

type InventoryError = {
  code:
    | "VALIDATION_ERROR" | "UNAUTHENTICATED" | "FORBIDDEN"
    | "NOT_FOUND" | "CONFLICT" | "INSUFFICIENT_STOCK"
    | "IDEMPOTENCY_MISMATCH" | "STALE_VERSION"
    | "DEPENDENCY_UNAVAILABLE" | "RETRYABLE"
    | "INTERNAL_ERROR";
  message: string;       // safe, non-sensitive message
  retryable: boolean;
  fieldErrors?: Record<string, string>;
};

type Availability = {
  skuId: string;
  locationId: string;
  sellableQuantity: number;
  displayStatus: "available" | "limited" | "unavailable" | "coming_soon";
  asOf: string;
};

type ReservationReceipt = {
  reservationId: string;
  status: "active" | "partially_fulfilled" | "committed" | "released" | "expired";
  expiresAt?: string;
  lines: Array<{ skuId: string; allocatedQuantity: number }>;
};

type UnitSummary = {
  unitId: string;
  skuId: string;
  locationId: string;
  lifecycleStatus: string;
  version: number;
  // Raw serial/IMEI is intentionally excluded.
};
```

Actor context is constructed internally for each request; it is not a public request-body field.

## 5. Command contracts

| Command | Required intent/input | Server-side behavior | Success result |
|---|---|---|---|
| Resolve SKU | SKU code or approved identifier lookup | Normalize and resolve against catalog/inventory; enforce identifier-read permission | Safe SKU summary; unit summary only when authorized |
| Receive | Receipt reference, SKU lines, quantities, source, idempotency metadata | Validate receiving permission, receipt state, quantities, source, and cost-domain reference; create stock and movements atomically | Receipt ID and accepted quantities |
| Inspect | Unit/lot reference, condition grade, test outcomes, evidence references | Validate inspection permission and permitted transition; retain evidence references; avoid unrestricted identifier exposure | Inspection ID and resulting stock state |
| Reserve | Owner reference, SKU lines or unit allocations, expiry policy, idempotency metadata | Validate owner and location scope; atomically allocate available stock | Reservation receipt |
| Release | Reservation ID and reason code | Validate reservation state and authority; release only remaining allocations | Updated reservation receipt |
| Commit | Reservation ID and authoritative order/fulfillment reference | Verify reservation and upstream transaction state; atomically commit stock movement | Committed allocation reference |
| Transfer | Source, destination, unit/lot allocations, reason, idempotency metadata | Validate both locations and permissions; record paired movement semantics atomically | Transfer ID and resulting state |
| Adjust | Target, signed delta or unit transition, reason, evidence, idempotency metadata | Require elevated permission and reason; apply compensating movement; never overwrite history | Adjustment/movement ID |
| Hold | Target, hold type, reason, optional expiry | Validate hold authority; block applicable sellable availability | Hold ID and effective status |
| Release hold | Hold ID, reason | Validate release authority and hold state | Released hold status |
| Get availability | SKU and location or approved location scope | Read authoritative availability/projection and freshness metadata | Availability response |
| Reconcile | Scope, cutoff/window, reconciliation mode | Compare ledger, units/lots, reservations, and projection; produce discrepancy report; mutations require separately authorized correction workflow | Reconciliation report ID and counts |

No command should accept a free-form client status as an instruction to bypass lifecycle rules.

## 6. Idempotency and concurrency

- Every stock-mutating command requires an idempotency key.
- Persist the key with operation scope, request fingerprint, result reference, and completion state.
- Same key + same canonical request returns the original result; same key + different request returns `IDEMPOTENCY_MISMATCH`.
- Concurrent duplicate requests must not create duplicate receipts, movements, reservations, or transfers.
- Serialized unit commands validate expected version and current state within the same transaction.
- Quantity-lot reservations and adjustments use row-level locking or atomic conditional updates. The transaction must fail cleanly if remaining quantity is insufficient.
- Reservation expiry is a server-controlled transition. A client countdown is informational only.
- A timeout after commit must be recoverable by retrying the same idempotency key and reading the original result.
- Use bounded retries only for known transient conflicts/dependency failures; do not automatically retry validation, permission, or idempotency mismatch errors.

## 7. Event and outbox contract

A successful state-changing transaction writes its outbox event in the same database transaction.

Illustrative envelope:

```ts
type InventoryEvent<T> = {
  eventId: string;
  eventType: string;
  schemaVersion: number;
  occurredAt: string;
  aggregateType: "unit" | "quantity_lot" | "reservation" | "receipt" | "transfer";
  aggregateId: string;
  correlationId?: string;
  causationId?: string;
  payload: T; // allowlisted business fields only
};
```

Candidate events:
- `inventory.received`
- `inventory.inspected`
- `inventory.reserved`
- `inventory.reservation_released`
- `inventory.reservation_expired`
- `inventory.committed`
- `inventory.transferred`
- `inventory.adjusted`
- `inventory.held`
- `inventory.hold_released`
- `inventory.reconciled`

Consumers (website availability, POS, shipping/pickup, analytics, notifications) must be idempotent and tolerate at-least-once delivery. Failed delivery is retried with bounded backoff and dead-letter/operational review. Event payloads must not contain raw serial/IMEI, credentials, payment data, unnecessary personal data, or secrets.

## 8. Error handling

- `VALIDATION_ERROR`: malformed or incomplete request; correct input before retry.
- `UNAUTHENTICATED`: no valid server session; re-authenticate.
- `FORBIDDEN`: actor lacks permission or location scope; do not retry without an authorization change.
- `NOT_FOUND`: target does not exist or is not visible to the caller; avoid leaking protected record existence.
- `CONFLICT`: invalid lifecycle transition, already-completed operation, or incompatible state.
- `INSUFFICIENT_STOCK`: available allocation is below requested quantity.
- `IDEMPOTENCY_MISMATCH`: same key reused with a different canonical request.
- `STALE_VERSION`: record changed since caller's expected version; reload and make a new decision.
- `DEPENDENCY_UNAVAILABLE` / `RETRYABLE`: transient dependency or transaction contention; retry same key with backoff.
- `INTERNAL_ERROR`: unexpected failure; return a safe message and server request ID, not stack traces or database internals.

Logs should include request/correlation IDs, operation, outcome, timing, and safe record references. Redact credentials, payment data, raw identifiers, and unnecessary personal data.

## 9. Test matrix

Tests below are required planning targets. **No tests or commands are claimed to have been executed.**

| Area | Scenario | Expected assertion |
|---|---|---|
| Unit | SKU normalization and lookup | Stable normalization; invalid values rejected |
| Unit | Lifecycle transition rules | Only documented transitions accepted |
| Unit | Quantity and condition validation | Zero/negative/invalid quantities rejected |
| Unit | Error mapping | Stable safe error codes; no internal detail leakage |
| Integration | Receive serialized unit | Unit, receipt line, movement, and outbox commit atomically |
| Integration | Receive quantity lot | Lot quantity and ledger reconcile |
| Integration | Transfer between locations | Source/destination changes and movement history agree |
| Integration | Return disposition | Only approved Build 017 disposition can alter stock |
| Integration | Reservation then commit | Allocation transitions once and links to authoritative order |
| Security | Anonymous request | No protected inventory data or mutation |
| Security | Authenticated customer mutation | Denied unless explicitly authorized |
| Security | Employee without location scope | Denied for out-of-scope location |
| Security | Client forges actor/role/cost/availability | Forged values ignored or rejected |
| Security | Identifier lookup without permission | Denied and raw identifiers not leaked |
| Concurrency | Two reservations compete for one unit | At most one succeeds |
| Concurrency | Parallel quantity reservations | Total committed allocation never exceeds available quantity |
| Concurrency | Two updates with same expected version | One succeeds; stale request conflicts |
| Idempotency | Same key and same request replayed | Original result returned; no duplicate movement |
| Idempotency | Same key with different payload | Idempotency mismatch; no mutation |
| Failure | Process fails before transaction commit | No partial stock state or outbox event |
| Failure | Process fails after commit before response | Retry returns committed result |
| Events | Consumer receives duplicate event | Consumer applies effect once |
| Events | Consumer unavailable | Outbox remains pending and retries safely |
| Reconciliation | Ledger and projection agree | No discrepancy reported |
| Reconciliation | Projection drift introduced in test fixture | Discrepancy detected; correction is separately authorized |
| Privacy | Logs and event payload inspection | No raw serial/IMEI, credentials, payment data, or secrets |

## 10. Release gates

Before implementation:
1. Confirm Build 004 server-side session and actor resolution design; do not assume it is already integrated in the app.
2. Approve the permission mapping and location-scope model.
3. Approve SKU/catalog ownership and serialized-versus-quantity stock rules.
4. Complete the database/security preflight when the user chooses to resume inspections.
5. Review API contracts and test cases with the implementation plan.

Before production:
- All applicable test categories pass in a non-production environment.
- Concurrency and idempotency behavior is demonstrated under parallel load.
- Security and identifier-redaction tests pass.
- Reconciliation and operational alerting are verified.
- Explicit production approval is recorded.

## 11. Completion boundary

This document defines a proposed contract and test plan only. It does not create routes, services, database functions, migrations, policies, tests, or integrations. It does not authorize live payment testing or production changes.
