# Build 010.84 — Inventory Cycle Counts, Physical Audits & Automated Stock Adjustments

**Status:** Additive implementation contract committed on an isolated feature branch. No live count workflow, inventory adjustment API, database migration, stock mutation, or production deployment is claimed.

## 1. Audit findings

Repository searches on the Build 010.83 line did not locate verified cycle-count, physical-audit, blind-count, stock-adjustment, or count-session runtime components. Build 008 specifies full and cycle counts, immutable expected snapshots, blind counting, variance review, approved compensating movements, and recurring reconciliation, but explicitly states that the inventory implementation is not established by that document. Build 010.75 and 010.79 also define count/adjustment requirements and state that the canonical inventory schema and posting service must be verified before runtime changes.

Do not invent inventory tables, adjustment RPCs, location IDs, employee permissions, or a parallel stock master. Inspect the target Supabase schema, ledger, RLS, identity matrix, location master, count/receiving/transfer/returns/POS source records, and audit service before implementation.

## 2. Objective

Create a controlled, evidence-backed process to compare physical stock with the canonical inventory ledger, investigate variances, obtain independent approvals, and post only authorized compensating movements. Count submission itself must never change inventory.

## 3. Count scope and scheduling

Support count plans by:
- Full store/warehouse.
- Location or sub-location.
- Department, category, brand, or product family.
- Random sample and risk-based sample.
- High-value, serialized, or restricted inventory.
- Targeted recount after discrepancy, transfer, receiving, return, or posting exception.

Each plan records stable ID/version, scope definition, locations, included/excluded statuses, scheduled window, policy version, reason, risk level, assigned counters, independent reviewer, start/end, and state. Preserve plan history if scope or schedule changes.

## 4. Snapshot and count-session controls

- Capture an immutable expected balance snapshot and ledger revision at the defined count cutoff.
- Identify product/unit, location, condition/status, quantity unit, and serialized custody scope.
- Support blind counts that do not reveal expected quantities to counters where policy requires.
- Record each observation with counter, timestamp, scan/manual method, quantity, serial/IMEI vault reference where applicable, condition, evidence, and correction history.
- Prevent duplicate scans or duplicate count lines from inflating observed quantity.
- Support count-in-progress controls and documented treatment of receipts, sales, transfers, reservations, returns, and other movements occurring during the count window.
- Either freeze scoped movements under approved operational policy or use a reproducible cutoff/replay model; never compare inconsistent time windows.
- Recounts are separate linked observations, not overwrites of original counts.

## 5. Variance calculation and investigation

Compare the observed count against the immutable expected snapshot adjusted only by verified, in-scope movements after the cutoff. Categorize:
- Shortage / possible shrink.
- Overages / unidentified stock.
- Wrong location or custody.
- Condition/status mismatch.
- Duplicate/missing serialized unit.
- Unposted receiving, sale, transfer, return, or write-off.
- Timing/cutoff mismatch.
- Data integrity or source-system discrepancy.

Every variance records expected quantity, observed quantity, delta, value basis if approved, item/location references, source ledger revision, related order/transfer/receipt/return references, evidence, reason code, risk/severity, assigned owner, aging, investigation notes, recount result, and state.

A variance is an exception, not an authorized stock correction. Do not net unrelated shortages and overages without a documented policy and reviewer approval.

## 6. Review and approval workflow

Required logical states:
1. Planned.
2. Open / counting.
3. Submitted.
4. Variance review.
5. Recount requested (where needed).
6. Pending approval.
7. Approved or rejected.
8. Posting pending.
9. Posted / reconciled.
10. Closed.

Approval binds to the exact count snapshot, observed lines, evidence, variance calculation, reason, and adjustment proposal version. Any material change invalidates approval and requires re-review.

Enforce separation of duties where configured: the counter cannot approve their own material adjustment. Apply thresholds by quantity, cost value, product class, location, repeated variance, and risk. High-value or serialized exceptions may require a second approver or executive review. Rejection preserves the count and explanation without posting stock.

## 7. Authorized stock adjustments

- Post only through the canonical inventory ledger's approved compensating-movement operation.
- Every adjustment references count session, variance line, approval, reason code, item/unit, location, quantity delta, actor, reviewer, source evidence, timestamp, ledger revision, and idempotency/correlation key.
- Use append-only history; never edit or delete original movements or count observations.
- Use atomic posting or durable outbox/retry with reconciliation if the ledger boundary is distributed.
- Duplicate/replayed posting must create exactly one compensating movement.
- A failed posting remains pending/exception; the count must not be marked reconciled.
- Enforce current balance/version checks to prevent a stale count from overwriting later activity.
- Serialized devices require explicit unit-level identity and custody reconciliation; do not post ambiguous quantity adjustments against an unidentified IMEI/serial.
- No adjustment may silently change purchase cost, landed cost, approved selling price, order state, payment state, or customer-facing listing content.

## 8. Security, audit and privacy

- Verify employee identity server-side and enforce count, review, approval, adjustment, export, and location permissions.
- Apply row-level security and location scope to all reads and writes.
- Restrict high-value, serialized, employee-activity, and cost-value details to authorized roles.
- Encrypt and mask serial/IMEI; do not include restricted values in general logs, notifications, exports, or customer payloads.
- Audit plan creation/revision, assignment, snapshot, scan, manual count, recount, evidence change, variance classification, approval/rejection, posting, retry, override, and closure.
- Require reason and evidence for manual quantity entry, scope changes, late movements, recount overrides, and exceptional approvals.

## 9. Automation and reporting

Automate scheduled count reminders, risk-based count generation, aging alerts, variance assignment, recount requests, approval routing, safe idempotent posting retries, and targeted reconciliation. Automation may detect, notify, and retry; it may not approve a variance or independently create an adjustment.

Dashboards report count coverage, count accuracy, unresolved variance by age/location/category, shrinkage trends, repeated variance, adjustment volume/value, approval latency, recount rate, and posting failures. Distinguish actual ledger facts from estimates and unresolved observations. Reports respect employee/location access scope.

## 10. Acceptance and regression tests

- Count snapshot is immutable and tied to a precise ledger revision/cutoff.
- Blind counters cannot read expected quantities when blind-count policy applies.
- Duplicate scans/manual lines do not inflate observed counts.
- Concurrent inventory movements are handled using the documented cutoff/freeze/replay policy.
- Recount preserves the original count and all evidence.
- Variance submission never changes on-hand, ATP, reservation, or ledger balances.
- Unauthorized users cannot count, approve, adjust, or view restricted scopes.
- Counter cannot approve own adjustment where separation-of-duties policy applies.
- Approval becomes invalid after material proposal/evidence/scope revision.
- Adjustment requires reason, evidence, authorized approval, and current ledger version.
- Replayed adjustment command posts exactly once.
- Failed posting remains pending and recoverable; it does not mark the count reconciled.
- Serialized-unit mismatch is quarantined for investigation and cannot be silently quantity-adjusted.
- Original ledger movements and count records remain immutable.
- Tests reconcile POS, receiving, transfers, returns, write-offs, reservations, and count cutoff activity.
- Regression tests preserve customer sign-in, employee sign-in, product viewing, POS, warehouse, receiving, returns, transfers, and website availability behavior.

## 11. Runtime implementation gates

Do not mark Build 010.84 implemented or live until:
1. Canonical inventory ledger, product/unit, location, identity, audit, and movement schemas are inspected in the target environment.
2. Count snapshot/cutoff semantics and treatment of live movements are approved by operations and finance.
3. Role, location, blind-count, separation-of-duties, and approval thresholds are approved.
4. Additive migrations, RLS policies, and rollback strategy are reviewed.
5. Count plan/session, scan/manual entry, variance review, recount, approval, and adjustment UI/API are implemented.
6. Approved compensating movement posting is integrated with idempotency and recovery.
7. Unit, integration, concurrency, authorization, RLS, and end-to-end tests pass.
8. Staging counts reconcile to ledger revisions and all approved adjustments post exactly once.
9. Customer/employee sign-in, catalog, POS, warehouse, receiving, returns, transfers, and website regressions pass.
10. Production deployment and post-deploy evidence are recorded with exact commit and environment.

**Release note:** This contract is not an inventory count, stock correction, adjustment authorization, production migration, or deployment approval. No runtime feature or production stock change is claimed by this document.
