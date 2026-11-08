# Master Build 011 — Purchasing & Receiving Integration

Status: **integration contract / implementation gate**. This branch is isolated from `main`. This document does not claim that the purchasing, receiving, inventory, supplier, or finance workflows are production-ready.

## Purpose

Unify MME OS procurement and receiving capabilities under Master Build 011 without duplicating the work already recorded in the detailed 009.xx and 010.xx implementation streams. Build 011 is the master capability and integration owner; it does not renumber or replace the detailed implementation history.

## Repository baseline

- Default branch inspected: `main`, commit `aadf39502b42c87508f4e8b07d8a4a2cece74eeb`.
- The latest default-branch commit is a revert restoring the warehouse dashboard after an unintended default-branch write.
- Existing procurement feature branches are materially ahead of and diverged from `main`; they must not be merged wholesale without a controlled file-level reconciliation.
- Recent Vercel deployment history contains failed deployments. A separate Hobby-plan cron-frequency restriction was reported for a five-minute schedule. This build does not change schedules, plan level, production configuration, or deployment state.

## Existing work crosswalk

| Existing record | Scope found | Current evidence / boundary |
|---|---|---|
| Build 009.57 / PR #53 | Purchasing command center | Draft PR; not merged |
| Build 009.58 / PR #54 | Receiving intake, inspection and serialized intake evidence | Draft PR; not merged |
| Build 009.59 / PR #55 | Inventory ledger and receipt stock posting | Draft PR; not merged; separate posting boundary |
| Builds 009.60–009.63 / PRs #56–#59 | Transfers, reservations, fulfillment and reverse logistics | Draft PR chain; not merged |
| Build 010.41 | Vendor directory, purchase orders, lines, approvals, partial receiving and invoice register | Existing isolated branch code and documentation; not production-verified |
| Build 010.70 | Supplier catalog, vendor offers, quote lines and price comparison | Existing isolated branch; supplier-entered prices are not independently verified |
| Build 010.71 | Price observations and landed-cost scenario evidence | Existing isolated branch; documentation/migration scope must be reconciled before use |
| Builds 010.76–010.77 | Inventory ledger API and database contracts | Contract-only records; canonical schema discovery remains a prerequisite |
| Build 010.80–010.82 | Purchase-order/receiving and multi-location transfer contracts | Contract-only records; no production migration or deployment claimed |

## Canonical source-of-truth decisions

These decisions are requirements for implementation, not assertions that the live database already conforms.

1. **Vendor identity:** retain one vendor master. Reuse the existing approved vendor record if validated; do not create a second supplier master for the supplier catalog.
2. **Product identity:** supplier catalog rows map to canonical MME inventory products. Never create duplicate MME product records from vendor SKUs.
3. **Purchase orders:** retain one purchase-order header and line authority. Preserve approval state, ordered quantity, received quantity, outstanding quantity, cancellation history and event history.
4. **Receiving:** receiving intake is the inspection and custody evidence boundary. Purchase-order receiving must consume only finalized, eligible intake quantities. Partial receipts and discrepancy resolution must be explicit.
5. **Inventory posting:** exactly one authoritative transaction posts each accepted receipt into stock. It must atomically persist the movement, stock balance/projection, source receipt state, idempotency result and audit event. No second receipt RPC may independently increase stock.
6. **Serialized electronics:** apply serial/IMEI checks based on trusted product tracking policy and receiving evidence. Mask serial/IMEI in routine views and logs.
7. **Cost:** preserve currency and approved cost source. Landed-cost components must be evidenced and allocated under a documented policy; do not silently convert currencies or create a competing cost basis.
8. **Invoices and payables:** invoice capture/matching is not payment execution. Vendor payment, ACH, bank connectivity, accounting export and tax settlement remain separately authorized finance capabilities.
9. **Authorization:** resolve active employee identity and role through the canonical MME identity/permission source. Do not trust client-supplied actor IDs or broad role-name allowlists as the final authorization model.
10. **Auditability:** all approval, receipt, adjustment, exception and reconciliation actions must have actor, timestamp, reason, source reference and correlation/idempotency identity.

## Master Build 011 functional scope

### A. Procurement planning
- Requisition/request capture with business justification, requested-by identity, location, target date and line details.
- Budget availability and spending-limit checks.
- Vendor/offer comparison with currency, MOQ, lead time, availability, quote validity and verification status.
- Reorder suggestions may be advisory; automatic purchase commitment is prohibited without approval.

### B. Vendor and catalog management
- Vendor status, contacts, terms reference and document records.
- Vendor-specific catalog items mapped to canonical MME products.
- Supplier offers and quote history with source and verification timestamps.
- Duplicate detection and controlled vendor/product mapping.

### C. Purchase orders and approvals
- Draft, submit, approve, reject, revise, cancel and close lifecycle.
- Approval thresholds and segregation of duties based on an approved permission matrix.
- Header and line creation must be atomic or recoverable without orphaned partial orders.
- Approved PO revisions must retain version history and approval evidence.

### D. Receiving and inspection
- Receive against an approved PO and authorized location.
- Support partial, complete, overage, shortage, damage, mismatch and rejected quantities.
- Capture serial/IMEI, device condition, inspection/test evidence and custody where applicable.
- Prevent duplicate receipt and over-receipt; use idempotency keys and transaction locking.
- Route discrepancies to a review queue; do not silently post disputed stock.

### E. Inventory and cost handoff
- One receipt-posting transaction and one authoritative movement journal.
- Distinguish on-hand, reserved, available-to-promise and in-transit quantities.
- Reconcile PO ordered/received quantities against intake and ledger records.
- Preserve cost components and currency; expose variance evidence to finance.

### F. Invoice matching and finance handoff
- Match vendor invoice to approved PO and accepted receipt evidence.
- Flag price, quantity, tax, freight, currency and duplicate-invoice discrepancies.
- Keep invoice status distinct from payment status.
- Require authorized finance approval before any payment instruction or accounting export.

### G. Monitoring and analytics
- Open requisitions, approvals waiting, POs by status, inbound deliveries, receipt discrepancies, vendor performance and spend by category/location.
- Track audit events, failed posting attempts, retries, outbox delivery and unresolved exceptions.
- Alerts and escalation must be idempotent and observable.

## Required integration map

- Product Catalog / Inventory Master: canonical product and tracking policy.
- Inventory Ledger: single posting authority.
- Warehouse / Receiving: intake, inspection, custody and put-away evidence.
- Identity / Roles / Audit: actor authentication, location scope and approval authority.
- Finance / Accounts Payable / Accounting: invoice matching and controlled downstream handoff.
- Scheduling / Store Operations: receiving location, staffing and delivery windows.
- Workflow Automation / Notifications: approvals, discrepancies, overdue tasks and retries.
- Analytics / Executive Dashboard: procurement and receiving metrics.

## Implementation sequence and release gates

1. Inventory all migrations, live Supabase tables/functions, RLS policies, grants, indexes and canonical keys. Compare against both repository branches and the connected database; do not infer schema from documentation alone.
2. Produce a file-level merge map for PRs #53–#59 and the 010.41/010.70/010.71 branches. Reconcile common files and migration ordering before copying code.
3. Select and document one canonical vendor, product, PO, receiving, inventory movement, location, identity and cost source.
4. Implement the additive integration on this Build 011 branch. Do not modify `main` directly.
5. Add ordered migrations only for missing capabilities. Include rollback notes, RLS, grants, constraints, indexes and service-role boundaries.
6. Add API and UI integration with server-side permission checks, strict request validation, idempotency and safe error semantics.
7. Run lint, build, all affected 009.57–009.63 and 010.41/010.70/010.71 suites, plus PostgreSQL migration replay and concurrency/integration tests.
8. Open a reviewable pull request. Do not merge, apply production migrations, or deploy until checks pass and release authorization is explicit.

## Mandatory tests

- Unauthorized, customer, inactive and wrong-location actors are denied.
- Same idempotency key and same payload replays the original receipt; changed payload conflicts.
- Concurrent duplicate receipt attempts post exactly once.
- Partial receipt updates the correct outstanding quantity.
- Over-receipt and disputed receipt cannot post without authorized resolution.
- Serialized device requires valid unique identity and required inspection/custody evidence.
- Inventory movement, balance, PO/receipt state and audit event commit or roll back together.
- Failed downstream finance integration cannot falsely mark an invoice paid.
- Vendor catalog mapping cannot create duplicate canonical products.
- RLS, grants, role permissions, masking and audit append-only rules are verified.
- Existing POS, catalog, inventory, warehouse, purchasing and receiving regressions pass.

## Explicit non-goals for this stage

- No vendor payment execution or bank/ACH connection.
- No automatic external purchase commitment.
- No automatic FX conversion.
- No production schema migration.
- No production deployment or Vercel plan/schedule change.
- No merge of entire divergent feature branches.

## Completion definition

Master Build 011 is complete only after the canonical-source audit, additive implementation, migration replay, automated tests, permission/security review, end-to-end purchasing-to-receiving-to-ledger verification and review approval all pass. A branch, specification, or draft PR alone is not implementation completion.
