# Build 005.9 — Non-Production Test Strategy and Data Plan

**Status:** Test planning only  
**Branch:** `implementation/build-005-inventory-core`  
**Scope:** Defines safe test environments, synthetic fixtures, scenario coverage, and evidence requirements for Build 005. No test code, seed scripts, SQL, database objects, or deployments are changed by this document.

## 1. Purpose

Establish a repeatable way to verify Inventory Core before any pilot or production release. Testing must prove stock integrity, authorization, concurrency, idempotency, privacy, and cross-channel consistency using synthetic data in a non-production environment.

This plan does not authorize additional database inspection. The previously requested pause remains in effect until the user explicitly resumes it.

## 2. Environment and safety boundaries

- Use a dedicated non-production Supabase project and non-production application configuration.
- Confirm the target environment before running any future test or seed command.
- Never point destructive seed/reset commands at production.
- Use synthetic customer, employee, supplier, order, product, serial/IMEI, and payment-reference data.
- Do not use real customer records, real serial/IMEI values, payment credentials, or production secrets.
- Keep test secrets in environment configuration; never commit them.
- Disable outbound customer notifications, live payment capture, real shipping labels, and external marketplace publication in test runs unless a separately approved sandbox integration is in use.
- Any payment-related integration test must use the payment provider's sandbox mode and test credentials. No live payment test is authorized here.
- Reset or clean test data only through a documented, environment-verified procedure.

## 3. Synthetic fixture catalogue

Create deterministic fixture sets with stable IDs so tests can be repeated and failures reproduced.

### 3.1 Identity and authorization fixtures

- Authorized inventory manager with receive, inspect, transfer, hold, and reconcile permissions.
- Sales associate with SKU lookup, reservation, and sale-commit permissions for one location.
- Employee without inventory mutation permissions.
- Employee authorized at Store A but not Store B.
- Customer account with read-only storefront access.
- Unauthenticated request context.
- Disabled/frozen identity context where supported by the approved Build 004 rules.

All actor identity and permissions must be resolved through the server-side identity layer. Test fixtures must not simulate authorization by trusting client-provided role fields.

### 3.2 Catalog and inventory fixtures

- Serialized television SKU with two unique synthetic unit identifiers.
- Serialized laptop SKU with two synthetic units.
- Serialized cellphone SKU with synthetic IMEI-like values that cannot collide with real identifiers.
- Quantity-based accessory SKU with a known opening quantity.
- Quantity-based cable SKU with a separate location balance.
- SKU with no stock and an approved coming-soon display state.
- Inactive SKU and inactive location.
- Unit in inspection/quarantine, held, reserved, available, sold/committed, and transferred states.
- Quantity lot with known received, reserved, held, and available quantities.

### 3.3 Receiving and cost fixtures

- Receipt with several different SKU types and unequal quantities.
- Receipt with serialized units and quantity-based lines.
- Receipt with partial fulfillment and short shipment.
- Receipt with duplicate external reference.
- Receipt with invalid quantity and missing required evidence.
- Cost allocation fixture with deliberately different item acquisition costs, proving that unlike items are not assigned an equal split by default.
- Cost adjustment fixture that references the acquisition/COGS owner rather than changing retail price.

### 3.4 Commerce and fulfillment fixtures

- Draft cart/order with no reservation.
- Active reservation with future expiry.
- Expired reservation.
- Reservation with partial fulfillment.
- Paid/authorized test order state from a sandbox or controlled test fixture.
- Cancelled order.
- Auction item with reserve not met.
- Auction item with completed winning order.
- Pickup order awaiting handoff.
- Shipment awaiting dispatch.
- Approved return disposition from a Build 017 test fixture.

Fixtures must not imply that payment authorization, order completion, or return approval has occurred unless the upstream test fixture explicitly represents that state.

## 4. Test layers

### Unit tests
Validate pure domain rules:
- SKU and identifier normalization;
- lifecycle transition matrix;
- quantity and condition validation;
- availability calculation;
- permission-to-command mapping;
- idempotency request fingerprint comparison;
- event schema validation and redaction.

### Service/integration tests
Validate transactional behavior:
- receiving and movement creation;
- inspection transitions;
- holds and releases;
- serialized and quantity reservations;
- reservation commit, expiry, and release;
- transfers and adjustments;
- outbox creation and consumer processing;
- reconciliation across source records and projections.

### Security tests
Validate:
- anonymous access denial;
- customer mutation denial;
- employee permission and location scope;
- forged actor/role/cost/price/location/availability claims;
- protected identifier access;
- direct table access and function execution boundaries;
- safe error responses and log redaction.

### Concurrency and resilience tests
Validate:
- simultaneous reservations for one serialized unit;
- simultaneous quantity reservations near available balance;
- duplicate requests with same idempotency key;
- same key with changed request payload;
- stale version updates;
- timeout before commit;
- timeout after commit but before response;
- outbox consumer outage, duplicate delivery, and replay;
- retry behavior under transient database contention.

### End-to-end tests
Validate representative journeys across receiving, POS, website, auction, returns, shipping, and pickup without bypassing Inventory Core.

## 5. Required scenario catalogue

| ID | Scenario | Expected result |
|---|---|---|
| T01 | Receive one serialized unit | One unit, one receipt line, one movement, one outbox event |
| T02 | Replay same receive request | Original result; no duplicate unit or movement |
| T03 | Receive quantity lot | Quantity and ledger totals reconcile |
| T04 | Partial receipt | Only accepted quantity becomes stock; remainder remains explicitly outstanding |
| T05 | Inspect and grade unit | Evidence and inspector recorded; valid transition only |
| T06 | Place hold | Held stock excluded from sellable availability |
| T07 | Release hold twice | First release succeeds; replay causes no second stock effect |
| T08 | Reserve one serialized unit twice concurrently | At most one reservation succeeds |
| T09 | Reserve quantity concurrently | Total allocation never exceeds available quantity |
| T10 | Expire reservation | Remaining allocation released exactly once |
| T11 | Commit reservation | Stock movement committed once against valid upstream order state |
| T12 | Transfer between locations | Source/destination ledger entries balance |
| T13 | Unauthorized adjustment | Denied; no stock change |
| T14 | Authorized adjustment | Reason/evidence recorded; compensating movement retained |
| T15 | Return with unapproved disposition | No inventory state change |
| T16 | Return with approved disposition | Only permitted stock transition applied |
| T17 | Storefront and POS availability | Same authoritative quantity/status and freshness policy |
| T18 | Forged client actor or cost | Values rejected/ignored; server authority remains intact |
| T19 | Raw serial/IMEI requested without permission | Denied or safely masked according to policy |
| T20 | Duplicate outbox delivery | Consumer applies business effect once |
| T21 | Outbox destination unavailable | Event remains retryable and observable |
| T22 | Availability projection drift | Reconciliation identifies discrepancy |
| T23 | Invalid location transfer | Denied; no partial movement |
| T24 | Process timeout after successful commit | Retry with same key returns original committed result |

## 6. Reconciliation invariants

The test suite must verify at least these invariants:

1. Every active serialized unit belongs to one SKU and one current location.
2. A serialized unit is not simultaneously represented in quantity stock.
3. Quantity on hand cannot become negative.
4. Sellable quantity never includes held, reserved, quarantined, or otherwise ineligible stock.
5. Active reservations cannot exceed eligible stock.
6. Every committed stock transition has corresponding movement history.
7. Receipt totals reconcile to stock created and receipt-line outstanding quantities.
8. Transfers balance across source and destination locations.
9. Reservation release/expiry cannot release the same allocation twice.
10. Availability projections reconcile to authoritative records within the documented freshness window.
11. Corrections preserve original movement history.
12. Outbox events correspond to committed state changes and do not disclose protected values.

## 7. Test evidence and reporting

For each run, record:
- test run ID and timestamp;
- branch and commit SHA;
- environment identifier (non-secret);
- application version;
- migration version, if migrations are later approved and applied;
- fixture-set version;
- scenario IDs and pass/fail results;
- sanitized logs and request/correlation IDs;
- defects, severity, owner, and remediation status.

Do not attach raw secrets, credentials, personal data, or unmasked identifiers to test reports.

A passing test suite is not sufficient if tests ran against the wrong environment or skipped critical scenarios. Evidence must identify the target environment and exact commit.

## 8. Failure severity and release gates

- **Critical:** unauthorized mutation, data loss, duplicate sale/stock commit, overselling, identity bypass, or sensitive-data exposure. Blocks pilot and release.
- **High:** ledger/receipt mismatch, reservation corruption, unrecoverable outbox loss, or failed recovery. Blocks pilot and release.
- **Medium:** recoverable workflow defect with controlled workaround and no data-integrity/security impact. Requires owner and target fix before broad rollout.
- **Low:** cosmetic or low-impact usability issue. Track and prioritize.

Release gate:
- All critical and high issues resolved.
- Required scenarios pass in non-production.
- Concurrency, idempotency, security, and reconciliation evidence is recorded.
- Recovery and restore procedure is demonstrated.
- Pilot approval is documented separately.

## 9. Completion boundary

This document is a test plan only. It does not create fixtures, run tests, seed a database, apply migrations, inspect Supabase, connect external systems, or authorize production activity.

**Next gate:** Review and approve this test plan. Actual test implementation begins only after the relevant environment and database preconditions are authorized and verified.
