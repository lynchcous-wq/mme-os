# Build 010.87 — Inventory Lifecycle Automation, Aging Alerts & Automated Disposition Workflows

**Status:** Additive implementation contract committed on an isolated feature branch. No live aging engine, lifecycle automation worker, markdown workflow, disposition service, write-off posting, migration, or production deployment is claimed.

## 1. Audit findings

Repository searches on the Build 010.86 line did not locate verified inventory aging, lifecycle automation, obsolete-stock disposition, dead-stock liquidation, or automated write-off runtime components. Build 008 defines separate product, physical-unit, inventory, listing, condition, and disposition lifecycles; it requires authorized return disposition, controlled write-offs, approved pricing, and aging metrics, but explicitly states that its architecture is a specification rather than proof of implementation. Builds 010.79, 010.84, 010.85, and 010.86 define exception, count, cost, and forecasting controls but do not establish these runtime services.

Do not invent inventory state tables, write-off RPCs, product price rules, warranty authority, return-inspection services, or accounting postings. Verify canonical product/unit, inventory ledger, reservation, transfer, receiving, POS/order, return/inspection, pricing, warranty, COGS/Accounting, identity, audit, and task/notification authorities before runtime changes.

## 2. Objective and lifecycle boundaries

Provide controlled, explainable lifecycle monitoring from receipt through inspection, availability, reservation, sale, return, repair, quarantine, clearance, supplier return, parts-only, and write-off. Automate detection, reminders, task routing, and recommendations. Any action that changes stock, price, condition, warranty, customer-facing listing, accounting value, or legal disposition requires the relevant authoritative workflow and approval.

Keep these independent state domains separate:
- Product/catalog and website listing state.
- Physical unit condition and inspection state.
- Inventory custody, location, reservation, and availability state.
- Order, payment, fulfillment, and return state.
- Warranty/repair claim state.
- Approved selling-price and promotion state.
- Accounting valuation, COGS, impairment, and write-off state.

One state transition must not imply another. For example, an aging alert does not make a unit damaged; a return/refund does not make stock sellable; a markdown request does not change the approved price; a write-off proposal does not remove stock.

## 3. Aging model and eligibility

Track age using explicit event timestamps and policy-specific clocks, including:
- Acquisition/receipt date.
- Date accepted into sellable condition.
- Date first made available.
- Time in current location/status.
- Reservation start and expiry.
- Transfer dispatch and destination receipt.
- Return receipt and inspection start.
- Repair/quarantine entry and resolution.
- Last sale/fulfillment and last verified demand activity.

Reports must disclose which clock and population they use. Separate age of the physical unit from age of catalog listing and age of a reservation or exception. Do not reset acquisition age on transfer, relisting, condition change, or data correction. Use event history to preserve original timestamps and traceable corrections.

Define aging cohorts and thresholds by product category, condition, acquisition channel, seasonality, lifecycle status, and location. Configurable examples may include 0–30, 31–60, 61–90, 91–120, and 120+ days, but no threshold is a universal default until approved by operations/finance.

Exclude or separately report sold, fulfilled, written-off, returned-to-vendor, in-transit, reserved, quarantined, damaged, repair, and inspection-required units. Clearly distinguish sellable aging from blocked/exception aging.

## 4. Lifecycle monitoring and exception detection

Detect and route:
- Slow-moving and no-sale inventory.
- Excess days of supply or overstock.
- Approaching warranty or vendor return windows where verified.
- Long-running reservations and abandoned holds.
- Stale receiving, inspection, quarantine, repair, or transfer states.
- Repeated failed condition checks or missing accessories.
- End-of-life/discontinued catalog references.
- Duplicate/invalid serial identifiers or custody gaps.
- Stock with missing acquisition cost, approved price, condition evidence, or location.
- Stale or failed website publication and inventory sync.
- Repeated count variance, shrink, and adjustment patterns.
- Potentially impaired, damaged, obsolete, or unsellable inventory requiring review.

Every alert includes rule/policy version, source snapshot, timestamp, scope, severity, confidence, owner, due date/SLA, evidence references, and deduplication key. Detection is not a finding of misconduct or proof of loss.

## 5. Recommended actions

For eligible units, present options as proposals with rationale, estimated effect, dependencies, and risk:
- Continue normal sale and monitor.
- Improve approved listing content/media or demonstration.
- Reposition to another authorized store/channel/location.
- Request approved promotion or markdown.
- Bundle or accessory offer under approved pricing rules.
- Repair, refurbish, regrade, or re-inspect.
- Return to supplier under verified contract/window.
- Route to parts-only or salvage review.
- Request donation/recycling or other approved disposition.
- Request accounting impairment or write-off review.

Recommendations must distinguish verified facts from estimates. Include current approved price, cost basis if authorized, days aged, verified demand/availability, condition, warranty, estimated recovery value, fees, and margin impact where data exists. No recommendation is itself an authorization.

## 6. Pricing and clearance controls

- Pricing service owns the active approved selling price.
- Inventory/lifecycle service may create a markdown request only.
- Approval binds to product/unit scope, old/new price versions, effective period, channel, margin floor, reason, and approver.
- Enforce category, condition, minimum-margin, promotional, and executive thresholds configured by authorized owners.
- Revalidate price and inventory before publication or checkout.
- Expired or superseded markdowns revert only through the approved pricing workflow.
- Never expose internal cost, supplier, or margin data to customers.
- Clearance labels and customer-facing condition descriptions must be accurate and approved.

## 7. Repair, return, supplier return, and disposition

- Returns authority owns eligibility, refund status, inspection, and disposition decision.
- A returned unit is not available until required inspection and approval pass.
- Repair/refurbishment requires authorized work order, custody/location, parts/labor evidence, quality checks, cost treatment, and regrade approval.
- Supplier return requires verified supplier authorization, return reference, shipping/custody evidence, and receipt/credit reconciliation.
- Parts-only, salvage, donation, recycling, and write-off require policy-specific approvals and chain-of-custody evidence.
- Inventory changes only through canonical compensating movements or disposition commands.
- Accounting impairment/write-off is separate from physical stock movement and requires Accounting authority.
- Payment refunds, vendor credits, customer credits, and insurance recoveries remain separate financial events.
- Preserve serialized-unit identity and chain of custody; mask/encrypt serial/IMEI in ordinary views.

## 8. Workflow and approval states

Suggested case states:
1. Detected.
2. Triaged.
3. Assigned.
4. Recommendation prepared.
5. Pending operational review.
6. Pending pricing/finance/compliance approval as applicable.
7. Approved / rejected / deferred.
8. Action in progress.
9. Awaiting verification or evidence.
10. Reconciled / closed.
11. Reopened.

Approval is bound to exact unit/product, location, condition, proposed action, price/cost/valuation assumptions, evidence, and policy version. Material changes invalidate approval. Apply separation of duties for high-value markdowns, write-offs, supplier returns, and serialized/high-risk disposition. Rejected/deferred actions preserve rationale and history.

## 9. Automation, tasks and notifications

Automate scheduled aging scans, rule evaluation, alert deduplication, task assignment, SLA reminders, escalation, stale-case reopening, safe retries, and dashboard refresh. Use stable event IDs and minimal payloads. Failed notifications do not cancel the underlying case.

Automation may detect, rank, remind, and prepare a proposal. It may not approve markdowns, alter prices, move stock, release quarantined units, create vendor returns, dispose of property, post write-offs, or alter accounting records without authorized workflow approval.

## 10. Reporting and controls

Provide role-scoped views for:
- Aging by category, brand, condition, acquisition batch, location, and channel.
- Sellable versus blocked/exception aging.
- Slow-moving, excess, obsolete, and end-of-life inventory.
- Warranty/return/repair windows and case aging.
- Recommended versus approved actions and realized outcomes.
- Markdown history and approved margin impact.
- Repair/return-to-vendor/parts/salvage/write-off pipeline.
- Inventory value at approved valuation date and policy.
- Recovered value, carrying cost, write-off value, and realized gross margin only when supported by reconciled accounting data.

Every metric states formula, source, as-of date, currency, included/excluded statuses, cost/price version, timezone, freshness, and actual-versus-estimated status. Enforce role, legal-entity, department, and location scope.

## 11. Security, audit and privacy

- Authenticate employees server-side; enforce role/action/location authorization and RLS.
- Separate lifecycle case creation, recommendation, approval, execution, and accounting posting permissions.
- Audit rule changes, threshold changes, alert generation, assignments, evidence, recommendation versions, approvals, price changes, physical movements, disposition, and closure.
- Preserve append-only event history; no silent status rewrites or deletion.
- Protect serial/IMEI, customer data, vendor records, cost, margin, and employee activity.
- Export and bulk-action permissions are independently controlled.
- AI classifications and recommendations are advisory, explainable, source-linked, and subject to human review.

## 12. Acceptance and regression tests

- Aging calculations use the correct source event and never reset on transfer/relisting.
- Cohort membership is reproducible from stored source snapshot and policy version.
- Reserved, in-transit, quarantined, damaged, repair, sold, and written-off stock is not incorrectly counted as sellable aging.
- Duplicate event delivery creates one alert/case per deduplication key.
- Stale or missing data produces a visible warning rather than false precision.
- Alert generation never changes stock, price, condition, listing, warranty, or accounting balances.
- Markdown proposal cannot change active price before Pricing approval.
- Expired approval cannot authorize publication.
- Returned goods cannot become available without authorized inspection/disposition.
- Repair, supplier return, parts-only, donation/recycling, and write-off preserve custody and evidence.
- Physical inventory posting and accounting impairment/write-off remain separate and reconcile through approved authorities.
- Unauthorized users cannot approve or execute restricted actions or read cost/serial details.
- Material proposal changes invalidate prior approval.
- Automation retries are idempotent and recoverable.
- Regression tests preserve customer sign-in, employee sign-in, catalog, POS, warehouse, receiving, transfers, cycle counts, valuation/COGS, returns, and website availability.

## 13. Runtime implementation gates

Do not mark Build 010.87 implemented or live until:
1. Canonical inventory, catalog, pricing, returns/inspection, warranty, repair, accounting, identity, audit, and task/notification authorities are inspected.
2. Aging clocks, cohorts, exception policies, and SLAs are approved by operations and finance.
3. Pricing thresholds, repair/return/vendor-return/disposal authority, and write-off accounting rules are approved by the accountable owners.
4. Additive migrations, RLS, event retention, and rollback strategy are reviewed.
5. Lifecycle monitoring, alert/task automation, case UI, recommendation UX, and authorized execution handoffs are implemented.
6. Canonical ledger, pricing, returns, warranty, and accounting integrations are idempotent and recoverable.
7. Unit, integration, permission, concurrency, privacy, and end-to-end tests pass.
8. Staging lifecycle events reconcile to source records and all physical/financial actions have matching approvals.
9. Regression tests preserve sign-in, catalog, POS, warehouse, receiving, transfers, counts, valuation/COGS, returns, and website behavior.
10. Operations, finance, security, and executive owners approve rollout; production deployment and post-deploy evidence record exact commit and environment.

**Release note:** This contract is not a live aging alert, markdown, repair, vendor return, write-off, disposal, stock movement, accounting adjustment, production migration, or deployment approval. No runtime lifecycle automation or disposition action is claimed by this document.
