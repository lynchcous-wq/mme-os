# Build 009.59 — Enterprise Inventory Ledger & Automated Stock Posting

## Objective
Create a traceable inventory subledger and controlled posting boundary from Build 009.58 receiving intake. Every stock change is an immutable ledger event; the location balance is a transactionally maintained projection.

## Posting lifecycle
Receiving intake staging -> finalized receiving session -> discrepancy check -> optional serialized-device validation -> idempotent ledger receipt -> cost layer -> weighted-average balance update -> audit record.

## Valuation
This version implements moving weighted-average cost per SKU, location and currency. Accepted receipt value includes the intake unit cost plus any landed-cost allocation already entered on the staging row. Currency conversion is not performed. FIFO is not claimed as implemented; cost layers are retained as traceable receipt layers for future depletion logic.

## Serialized electronics
The receiving staging flag `requires_serial_validation` must be set by the trusted receiving workflow for serialized product classes. When enabled, every accepted unit requires an accepted serial/IMEI record with passed device test and clear or not-applicable activation-lock status. This migration does not infer serialized status from a product catalog.

## Adjustments
Stock corrections are requested with a reason and explanation. A different reviewer must approve. The transaction checks that resulting on-hand quantity remains nonnegative and not below reserved quantity. Approved changes create immutable ledger entries.

## Reconciliation
A controlled reconciliation compares ledger quantity/value with the materialized balance and records matched or variance. Variances are evidence for investigation; no automatic balance rewrite is performed.

## Security and integrity
RLS enabled across all ledger tables; browser roles have no direct access. Service-role RPCs must be called only by trusted APIs which authenticate the actor, enforce role/location scope and approval permissions, and validate product/serial policy. Ledger and audit are append-only. Intake posting uses row locks, a SKU/location/currency advisory lock and a unique idempotency key.

## Dependencies
Build 009.57 purchasing, Build 009.58 receiving intake, approved inventory locations, trusted identity/role mapping, reservation integration and POS stock-decrement integration.

## Validation
Run `npm run lint`, `npm run test:build009:inventory-ledger`, and previous Build 009.53–009.58 suites. PostgreSQL integration tests must cover duplicate and concurrent intake posting, weighted average cost, multi-currency isolation, serial validation, adjustment segregation of duties, reserved-stock protection, and reconciliation variance.

## Rollout boundary
Draft implementation only. No POS sale decrement, reservation mutation, transfer workflow, live dashboard, barcode-device integration, FIFO depletion, accounting export, production migration replay or deployment is claimed.
