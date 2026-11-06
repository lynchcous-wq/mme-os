# Build 009.53 — Enterprise Returns, Exchanges & Refund Management

## Purpose
Provide a governed RMA workflow for customer return requests, eligibility review, receiving, device inspection, condition grading, inventory disposition, exchanges and refund approvals.

## Lifecycle
Customer request -> RMA case -> policy eligibility review -> authorization -> item receipt -> inspection/evidence -> condition grade -> disposition -> refund/exchange decision -> processor result -> closure.

## Item inspection
Record serial/IMEI reference, serial match, activation-lock state, battery health, screen, ports, cameras, accessories, defect notes, condition grade and evidence object paths. Store photos in private object storage and issue short-lived signed access URLs through an authorized application service. Do not put public photo URLs in the database.

## Condition and disposition
Grades: A, B, C, D, non_resellable. Dispositions: restock_new, restock_open_box, refurbishment, parts_recovery, vendor_return, quarantine, secure_disposal. Non-resellable, serial-mismatched, activation-locked or failed inspection items cannot be restocked as new/open-box. Inventory posting remains a separate trusted inventory-domain integration.

## Refund control
Refund amount and currency are explicit. A requester cannot approve their own refund. The decision ledger has an idempotency key. Processor execution is not performed in SQL; a trusted Stripe adapter must submit approved refunds using an idempotency key and reconcile webhook outcomes. Processor references are retained for audit. Refund success is not inferred from request submission.

## Exchange control
Replacement item/order references and approval status are tracked separately. Inventory reservation, pricing difference collection/refund and order creation require integration with the authoritative commerce services.

## Security
RLS is enabled for every table. Customers can read only their own case, item, refund and exchange status via active auth-to-person account links. Inspection records, evidence, internal notes and audit events remain service-role-only. Employee authorization and approval limits must be checked by the trusted API against the MME role/permission service before invoking service-role RPCs. Service-role credentials must never be exposed to browsers.

## Dependencies
Build 009.52 customer order portal; Build 017 return inspection/condition-grade standards; authoritative inventory, order and Stripe payment services.

## Validation
Run `npm run lint` and `npm run test:build009:returns-management`. PostgreSQL integration tests must verify ownership isolation, eligibility transitions, inspection safety gates, grade/disposition consistency, independent approvals, duplicate refund requests, processor reconciliation, evidence access controls and audit immutability.

## Rollout boundary
Implementation branch only. No live Stripe refund execution, inventory adjustment, replacement order creation, employee UI, photo upload UI, role permission enforcement or production migration is claimed.
