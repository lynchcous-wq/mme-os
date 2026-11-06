# Build 009.60 — Enterprise Inventory Transfers & Multi-Location Distribution

## Lifecycle
Draft -> line creation -> submission -> independent approval -> pick/pack -> dispatch -> in-transit -> destination receipt -> reconciliation.

## Stock accounting
Dispatch posts an immutable transfer_out ledger movement and reduces source-location on-hand and value. Destination receipt posts transfer_in at the source carrying cost and increases destination stock. Units not yet received remain represented by the open transfer and its shipment quantities, not as sellable destination stock.

## Controls
- Source and destination must differ.
- Transfer requires lines and independent reviewer approval.
- Approval checks available stock after reservations.
- Picking cannot exceed approved quantity; all approved quantity must be picked before dispatch.
- Serialized identifiers can be recorded per line; when identifiers are present their count must match dispatched units.
- Dispatch rechecks source availability under a row/advisory lock.
- Destination receipts cannot exceed remaining dispatched quantity.
- Damaged and missing goods create exception records; no damaged units enter available inventory.
- Transfer events are append-only.
- Trusted API must authenticate actors and enforce source/destination location permissions and role separation.

## Costing
Transfer-out uses source moving weighted-average cost. Destination transfer-in preserves that carrying cost. No FX conversion or intercompany markup is performed.

## Reconciliation
Compares dispatched, received, damaged and missing quantities. Unresolved or missing units keep the transfer in exception state for investigation.

## Security
RLS enabled on transfer tables; browser roles have no direct table access. RPCs are service-role only and must be mediated by a trusted API. Ledger and event history are append-only.

## Validation
Run `npm run lint`, `npm run test:build009:transfers`, and prior Build 009.53–009.59 suites. PostgreSQL integration tests must cover approval segregation, concurrent dispatch, source reservations, partial receipt, duplicate retries, serialized count mismatch, damage, missing shipment and reconciliation.

## Rollout boundary
Draft implementation only. No carrier API, live GPS tracking, warehouse scanner UI, automated route optimization, production migration replay or deployment is claimed.
