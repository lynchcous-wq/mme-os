# Build 009.58 — Enterprise Receiving, PO Reconciliation & Inventory Intake

## Lifecycle
Internal PO draft -> receiving session -> SKU/quantity verification -> serial/IMEI capture -> condition and damage inspection -> discrepancy resolution -> landed-cost evidence -> supplier invoice comparison -> inventory intake staging -> separately authorized inventory posting.

## Receiving controls
- Session must reference an existing internal PO draft and purchase request.
- SKU must match the request.
- Cumulative physical receipts cannot exceed requested quantity; excess is blocked for exception handling.
- Accepted, damaged and missing quantities are distinct.
- Serial, IMEI and barcode identifiers are globally unique in this receiving registry.
- Device activation-lock and test states are recorded; this does not itself certify device condition.

## Discrepancies
Short shipment and damage create exception records. Wrong SKU, serial mismatch, price mismatch and missing documents can be entered through the discrepancy workflow. A receiving session with unresolved exceptions or shortages is finalized as exception, not reconciled.

## Landed cost
Freight, insurance, duties, tax, handling, brokerage and other charges are recorded with currency and evidence. The summary only aggregates charges in the same currency; no FX conversion or fully allocated per-unit landed-cost posting is performed in this build.

## Accounts payable
Invoice amount is compared with accepted received-goods value and a user-supplied tolerance. Currency mismatch is blocked. This is a three-way-match foundation, not an AP payment authorization or accounting posting.

## Inventory intake boundary
Accepted quantities create staging rows with pending_inventory_post. No live stock table is mutated by this migration. Posting requires a later, explicitly authorized integration with inventory ledger, location, cost basis and idempotency controls.

## Security
RLS enabled on all receiving tables. Browser roles have no direct table access. RPCs are service-role only and must be invoked by trusted APIs that authenticate the actor, verify receiving/location permissions, enforce separation of duties and rate-limit scanning endpoints. Audit is append-only.

## Validation
Run `npm run lint`, `npm run test:build009:receiving`, and previous Build 009.53–009.57 suites. PostgreSQL integration tests must cover cumulative partial receipts, over-receipt, duplicate IMEI/serial, concurrent receiving, discrepancy resolution, currency variance, and intake idempotency.

## Rollout boundary
Draft implementation only. No barcode hardware integration, camera scanning UI, supplier EDI, live inventory posting, AP ledger posting/payment, production deployment or user-facing dashboard is claimed.
