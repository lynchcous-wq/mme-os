# Master Build 011.03 — Purchase Order Reconciliation

Status: **repository-level lifecycle and integration design committed; live schema verification pending**.
Branch: `implementation/build-011-purchasing-receiving-integration`.
Date: 2026-11-07.

## Objective

Reconcile the 009.57 budget-gated purchase-request workflow with the 010.41 formal purchase-order workflow into one controlled procurement lifecycle. Preserve detailed build identifiers and historical implementation work. Do not create a second writable PO system, apply a production migration, or assume either branch's schema is live.

## Source findings

### 009.57 — Procurement request and PO draft

The migration defines:
- Vendor quotes and quote evidence.
- Procurement budgets and committed amounts.
- Purchase requests linked to demand forecasts, quotes, vendors, budgets and destination locations.
- Location allocations.
- A purchase-order draft record with a reference, vendor, currency, total and draft status.
- Functions to create and approve purchase requests and create a draft PO reference.

Important limitations observed:
- The PO draft stores only a header-like draft record; it is not the formal line-level purchase order model.
- The purchase request is forecast/SKU-reference oriented and is not proven to map to canonical product/location IDs.
- The approval function takes a caller-supplied approver UUID and does not itself demonstrate a trusted MME identity/permission check.
- Budget commitment and approval behavior must be reconciled with cancellation, revision, partial delivery and closeout; do not assume a draft PO is a supplier-confirmed commitment.
- The migration depends on a demand-forecast table not established by this migration.

### 010.41 — Formal PO header, lines and events

The migration defines:
- `mme_purchase_orders` with vendor, location, status, currency and financial totals.
- `mme_purchase_order_lines` with canonical product ID, ordered/received quantities and unit cost.
- `mme_purchase_order_events` for state transitions.
- Vendor invoice records.
- A PO transition function and a direct PO receiving function.

Important limitations observed:
- The transition function takes a caller-supplied actor UUID and does not itself prove actor authorization.
- The receiving function directly increases inventory balances, writes inventory movements and updates received quantity. It conflicts with the staged 009.58/009.59 receiving-to-ledger architecture and must not be used as a second receipt-posting authority.
- The shown PO status check permits draft, submitted, approved, partially_received, received and cancelled. It does not represent rejected, closed, revision-pending or supplier-confirmation states.
- PO header totals are stored separately from line totals; the integrity rule tying subtotal, tax, shipping and line totals needs explicit validation.
- The invoice table's `paid` status is not proof of a payment settlement record and must not trigger or represent payment execution.

## Canonical logical lifecycle

The target lifecycle is one chain of linked records. The names below are logical states; final database enum values must be aligned to the verified live schema.

1. **Requisition draft** — requester, business reason, destination, requested date, canonical product lines, quantity and estimated cost.
2. **Submitted** — requester submits; record becomes immutable except through a versioned change request.
3. **Budget and policy validation** — validate active budget, currency, location scope, spend limits, quote validity, vendor approval and required sourcing evidence.
4. **Approval pending** — route by value/category/location and segregate requester, approver and receiving roles.
5. **Approved or rejected** — approval decision, authority, timestamp and reason are recorded. Rejection releases any reservation/commitment.
6. **PO draft** — formal PO header and lines created atomically from the approved request version. A request must not create duplicate PO drafts on retry.
7. **PO submitted to supplier** — record external submission method, submitted version, timestamp and delivery reference. This is not supplier acceptance.
8. **Supplier confirmed** — record confirmed quantities, prices, dates and supplier reference. Differences require revision approval.
9. **Partially received / fully received** — update only from accepted receiving evidence and the single inventory-ledger posting result. PO receipt state is derived from accepted quantities, not a direct stock mutation.
10. **Invoice matched / exception** — three-way match invoice to approved PO version and accepted receipt quantities/costs.
11. **Closed or cancelled** — close only when outstanding quantity, invoices and exceptions are resolved or explicitly waived. Cancellation preserves history and releases only unreceived/uncommitted amounts under finance policy.

## Canonical data boundaries

| Capability | Authority | Must not become |
|---|---|---|
| Vendor identity | One canonical vendor master selected in Build 011.02 after live audit | Duplicate procurement, finance and vendor-management masters |
| Product identity | Canonical MME inventory product | Supplier SKU or free-text product description |
| Destination | Canonical location ID | Unvalidated free-text location |
| Requisition | One request header and versioned request lines | Formal PO or receipt |
| Approval | Trusted MME identity/permission service plus approval policy | Client-provided approver UUID or role label |
| Budget | Finance-owned budget/commitment authority | A UI-only calculation |
| PO | One formal PO header, lines and append-only events | Separate draft and formal PO systems that can diverge |
| Receiving | Staged receiving/inspection record | Direct stock increment from a PO API |
| Inventory | One idempotent inventory-ledger posting transaction | Multiple receiving functions updating stock |
| Invoice | Invoice and match/exception record | Vendor payment record |
| Payment | Separately authorized AP/payment system | Invoice status set to paid by PO workflow |

## Target PO aggregate

The final implementation should expose one formal PO aggregate with:

### Header
- Stable PO ID and unique human-readable PO number.
- Canonical vendor ID and destination location ID.
- Source requisition ID and source request version.
- Currency and immutable approved commercial snapshot.
- Status and version number.
- Expected and supplier-confirmed delivery dates.
- Subtotal, tax, shipping, discounts and total with currency precision.
- Created/submitted/approved/confirmed timestamps and trusted actor references.
- Cancellation/closure reason and source references.

### Lines
- Stable line ID and PO ID.
- Canonical MME product ID and optional vendor catalog/offer reference.
- Supplier SKU and manufacturer part number as source identifiers, not product identity.
- Description snapshot, ordered quantity, accepted quantity and cancelled quantity.
- Unit cost, currency and discount/tax treatment.
- Destination allocation, expected delivery date and line status.
- Tracking requirements for serial/IMEI, condition and inspection where product policy requires them.

### Events and revisions
- Append-only event history for every state transition.
- Versioned revisions to quantities, prices, vendor, currency or delivery destination.
- Reapproval when a commercial revision crosses policy thresholds.
- Supplier acknowledgement evidence and external PO reference.
- Idempotency key for create, submit, acknowledge, cancel and other retryable operations.
- Correlation ID across requisition, PO, receiving, ledger and invoice records.

## Approval and financial controls

- Requester cannot approve their own requisition.
- PO approver must have active employee identity, relevant permission and authorized location/value scope.
- Separate vendor onboarding approval, requisition approval, PO approval, receiving acceptance, invoice approval and payment release.
- Approval thresholds are centrally configured, versioned and audited; do not hard-code a role-name allowlist as the only authorization rule.
- Budget is checked and reserved/committed atomically at the appropriate approved/issued state.
- Draft/rejected/cancelled requests must not leave stale commitments.
- PO revision must calculate the commitment delta atomically and release/re-reserve budget as applicable.
- Supplier submission is not supplier confirmation.
- Invoice approval is not payment settlement.
- No payment credentials, bank account secrets or ACH instructions belong in PO records.

## Required transactional invariants

1. A submitted request references an approved vendor and canonical products/locations.
2. An approval applies to a specific immutable request version and commercial snapshot.
3. PO header and all PO lines are created in one transaction or one recoverable idempotent command.
4. A retry of PO creation returns the same PO for the same approved request version; it cannot create a second PO.
5. A PO cannot be submitted unless required approval and budget checks are satisfied.
6. Supplier confirmation cannot silently overwrite approved prices or quantities; changes create a versioned revision.
7. Accepted receipt quantity cannot exceed the open PO quantity unless an authorized over-receipt exception is approved.
8. PO received quantity is reconciled to accepted receiving evidence and successful inventory ledger postings.
9. The PO service itself does not write inventory balances or movement rows.
10. Invoice match uses the approved PO version and accepted receipt evidence.
11. PO cancellation cannot erase receipt history, invoice history or ledger movements.
12. Audit events and outbox notifications are written transactionally with the corresponding state transition.

## API/service contract (logical, not yet implemented)

- `POST /api/procurement/requisitions` — create a draft request.
- `POST /api/procurement/requisitions/:id/submit` — submit a version.
- `POST /api/procurement/requisitions/:id/decision` — approve/reject with policy-enforced authority and reason.
- `POST /api/procurement/purchase-orders/from-requisition/:id` — create/retrieve idempotent formal PO.
- `POST /api/procurement/purchase-orders/:id/submit` — record supplier submission.
- `POST /api/procurement/purchase-orders/:id/acknowledgement` — record supplier confirmation or variance.
- `POST /api/procurement/purchase-orders/:id/revisions` — create versioned commercial change request.
- `POST /api/procurement/purchase-orders/:id/cancel` — cancel eligible unreceived quantities with reason.
- `GET /api/procurement/purchase-orders` — filtered, permission-scoped PO list.
- `GET /api/procurement/purchase-orders/:id` — PO aggregate, lines and event history.

All writes require server-side schema validation, active identity resolution, permission checks, location scoping, idempotency where applicable, audit and safe error handling. These routes are a proposed service boundary; no route code is claimed to exist or be deployed.

## Integration sequence

1. Requisition service consumes the canonical vendor/product/location sources.
2. Budget/approval policy validates request and reserves/commits budget according to finance policy.
3. PO aggregate is created from the approved immutable request snapshot.
4. Supplier submission and acknowledgement evidence update the PO lifecycle.
5. Receiving intake consumes PO lines and records accepted/rejected quantities.
6. Only the authorized inventory ledger posting transaction updates stock.
7. PO received quantities reconcile to posted accepted receipt quantities.
8. Invoice matching consumes PO and receipt snapshots.
9. Approved invoices hand off to the separately authorized AP/payment process.
10. Events feed notifications, procurement analytics and audit monitoring.

## Reconciliation and migration plan (not authorized yet)

1. Obtain live Supabase migration history and schema inventory.
2. Identify whether any PO/request/vendor/line/event records exist in production and determine their owning application paths.
3. Inspect all current code references and RPC callers for `mme_procurement_purchase_order_drafts`, `mme_purchase_orders`, `mme_purchase_order_lines` and associated functions.
4. Choose one canonical PO identity and record family based on live dependencies and data—not branch preference.
5. Produce an ID crosswalk for existing draft PO records to formal PO records, with duplicate/orphan and status reports.
6. Design additive compatibility views/adapters only if required; no parallel writable PO stores.
7. Replace/disable direct PO-to-inventory receiving writes only after the single staged intake-to-ledger path is verified and cutover is approved.
8. Build migration with constraints, RLS, grants, indexes, append-only event protection and rollback notes.
9. Replay migrations and run integration/concurrency tests on a disposable Supabase project.
10. Obtain code review and explicit release approval before production migration or deployment.

## Mandatory tests

- Requester cannot approve own request.
- Inactive employee, unauthorized role, wrong location and insufficient value scope are denied.
- Approval is bound to the exact request version; stale approvals fail.
- PO creation is atomic and idempotent under concurrent retries.
- No duplicate PO for a single approved request version.
- Budget commitment is atomic under concurrent approvals and cannot exceed available funds.
- Rejection/cancellation/revision correctly releases or adjusts budget.
- Header totals reconcile with line totals, tax, shipping, discounts and currency precision.
- Supplier acknowledgement variance requires approved revision.
- PO cancellation preserves receipt, invoice and audit history.
- PO API cannot directly mutate inventory balance/movement tables.
- Accepted receipts reconcile exactly once to ledger postings.
- Invoice match cannot mark an invoice paid or execute payment.
- RLS, grants, actor attribution, append-only audit and outbox retry behavior pass.
- Existing procurement, inventory, receiving, warehouse, POS and finance regression tests pass.

## Acceptance checklist

- [x] 009.57 request/quote/budget/PO-draft migration inspected.
- [x] 010.41 formal PO/line/event/invoice migration inspected.
- [x] Direct receiving-to-inventory conflict documented.
- [x] One logical PO lifecycle and aggregate defined.
- [x] Approval, budget, revision, cancellation and payment boundaries defined.
- [x] API/service contract and integration sequence documented.
- [ ] Live Supabase schema and data dependencies verified.
- [ ] Canonical live PO source selected.
- [ ] Draft-to-formal PO crosswalk approved.
- [ ] Additive implementation and migration completed.
- [ ] Disposable database, security and end-to-end tests passed.

## Completion status

Build 011.03's repository-level purchase-order reconciliation is documented. It is not a live database implementation and does not assert that POs can currently be created or processed in production. No database mutation, merge or deployment is performed by this document.
