# Build 009.57 — Enterprise Inventory Optimization & Purchasing Command Center

## Purpose
Turn demand forecasts into budget-aware, approval-gated purchase requests with vendor comparison evidence and location allocation.

## Vendor intelligence
Maintain approved vendor profiles, quote evidence, currency, MOQ, shipping, lead time and validity. Record fulfillment performance by promised/actual delivery and accepted quantity. Scorecards report observed on-time delivery and acceptance rates; they are descriptive, not predictive guarantees.

## Purchase request flow
Demand forecast -> current vendor quote -> approved vendor -> matching SKU and currency -> active budget -> purchase request -> independent approver -> budget commitment -> internal PO draft.

## Financial controls
- Requests must fit an active, date-valid budget in the same currency.
- Approval locks and rechecks the budget before commitment.
- Requesters cannot approve their own requests.
- Approval creates an internal PO draft only. It does not transmit an order, charge a card, initiate ACH, or create a supplier obligation.
- Cancellation/rejection budget release and change-order handling require a future controlled workflow; do not manually alter committed_amount.

## Location allocation
The initial request allocates the forecast quantity to its destination location. Multi-location split allocation and transfer optimization require a later workflow with quantity reconciliation and authoritative inventory integration.

## Recommendation boundaries
The forecast supplies suggested quantity. Vendor MOQ, price, shipping and lead time are captured, but this version does not optimize across multiple quotes, supplier capacity, tax, duties, landed freight, open purchase orders or cash-flow scenarios. Review these factors before approval.

## Security
RLS enabled on all tables; browser roles have no direct table access. Service-role functions must be called only from trusted APIs that enforce role, location, budget ownership, approval authority and vendor onboarding checks. Audit records are append-only.

## Dependencies
Build 009.56 demand forecasts and alerts; vendor master, inventory, finance budget authority, receiving and accounts payable integrations.

## Validation
Run `npm run lint`, `npm run test:build009:purchasing`, and previous Build 009.53–009.56 suites. PostgreSQL integration tests must verify quote expiry, SKU/currency mismatch, budget concurrency, independent approval, PO draft idempotency, vendor performance aggregation and location scope.

## Rollout boundary
Draft implementation only. No external PO transmission, payment, supplier portal, live quote ingestion, multi-quote optimization, cash-flow forecasting, production deployment or UI is claimed.
