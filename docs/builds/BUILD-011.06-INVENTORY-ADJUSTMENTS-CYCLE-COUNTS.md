# Master Build 011.06 — Inventory Adjustments & Cycle Counts

Status: **repository-level adjustment and cycle-count specification committed; live schema verification and runtime implementation pending**.
Branch: `implementation/build-011-purchasing-receiving-integration`.
Date: 2026-11-07.

## Objective

Provide auditable physical stock counts, variance investigation, controlled adjustment requests, independent approvals, loss/damage write-offs and inventory reconciliation. A physical count must never directly overwrite an inventory balance. Only an authorized, idempotent command may post an approved adjustment through the single inventory ledger defined by Build 011.05.

## Existing implementation inspected — Build 009.59

The 009.59 migration already includes:
- `mme_inventory_adjustment_requests` with SKU, location code, currency, quantity delta, unit cost, reason, explanation, status, requester, reviewer and ledger reference.
- A request function that records a pending adjustment.
- An approval function that rejects self-review, locks the balance, prevents negative stock and prevents adjustment below reserved quantity, then inserts a ledger entry and updates the balance in the same function transaction.
- `mme_inventory_reconciliation_runs` that compare ledger totals with balance projections.
- A reconciliation function and a location-stock view.
- Inventory audit events.

It does **not** define a complete physical cycle-count session, count assignments, blind count snapshots, recount workflow, count freeze/snapshot version, item-level count evidence, or a formal variance case lifecycle. Build 011.06 defines these missing controls.

## Existing risks to correct before using 009.59

1. **Noncanonical identity:** adjustments and reconciliation use SKU text, location code and currency, not verified canonical product/location IDs.
2. **Caller-supplied actors:** request, approve and reconcile functions accept actor UUIDs. Trusted identity must be derived server-side; permission and location scope must be checked independently of the UUID parameter.
3. **Approval policy:** self-approval is blocked, but approval threshold, approver scope, separation-of-duties, reason validation and multi-level approval are not sufficiently specified.
4. **Adjustment valuation:** positive adjustments use the submitted unit cost; negative adjustments use current average cost. The source of positive adjustment valuation must be evidenced and independently approved; found stock must not accept arbitrary cost.
5. **Reservation semantics:** the existing ledger movement types include reservation/release as signed quantity movements. Build 011.05 requires reservations to affect commitments, not physical on-hand. These must be separated before ledger reconciliation.
6. **Reconciliation arithmetic:** the current reconciliation function sums every ledger quantity delta. If reservation/release events are included in the same quantity sum, the calculated quantity is not physical on-hand. The target must reconcile physical movement types separately from reservation events.
7. **Adjustment idempotency:** approval uses a deterministic request-based idempotency key, but replay behavior, changed approval payload and duplicate concurrent calls require explicit tests and conflict semantics.
8. **Reconciliation scope:** current reconciliation compares ledger and balance for a SKU/location/currency tuple; the final model must reconcile canonical product/location physical quantities, valuation and serial/status buckets, without treating currency as a second physical stock identity.
9. **Count controls absent:** there is no complete cycle-count workflow in this migration; a reconciliation run is not a physical count and must not be presented as one.
10. **RLS/function hardening:** verify actual grants, security-definer ownership, safe search_path, function execute privileges and append-only audit protections in a disposable database.

## Cycle-count workflow

1. **Count plan** — manager creates a count plan by location, zone, category, product, ABC class, risk or scheduled frequency. Each plan has a policy version and scope.
2. **Snapshot** — system captures the expected on-hand and relevant status buckets at a defined inventory ledger/balance version and timestamp. The snapshot is immutable.
3. **Assignment** — count tasks are assigned to authorized employees. The default is blind count: counters do not see expected quantities or cost.
4. **Movement control** — use a location/stock-item count lock or a controlled movement journal so receipts, sales, transfers and reservations occurring during a count are consistently included or excluded. Never silently compare counts taken at different cutoffs.
5. **First count** — employee scans canonical product/barcode/serial and enters physical quantity by stock status and location/bin. Record counted-by, timestamp, device/source and evidence.
6. **Variance calculation** — compare count to snapshot adjusted by valid ledger events after snapshot cutoff. Show quantity and value variance to authorized reviewers, not blind counters.
7. **Recount** — material or policy-triggered variance requires an independent recount by a different employee. Preserve original count and recount; do not overwrite.
8. **Investigation** — record likely cause, evidence, related receiving/POS/transfer/return events, serial-level differences and responsible work queue. Do not presume employee theft or fault.
9. **Disposition** — classify as matched, timing difference, data error, found stock, loss, damage, wrong location, serial mismatch, or unresolved. Require notes/evidence for material variances.
10. **Adjustment request** — generate an adjustment request referencing the count line, snapshot version, observed count, calculated delta and reason. No direct balance write.
11. **Approval** — independent authorized approver reviews evidence, quantity/value impact and policy thresholds. Multi-level approval may be required.
12. **Ledger posting** — post approved delta once through the canonical inventory command; append immutable ledger and audit events.
13. **Closeout** — reconcile count lines, adjustments, unresolved exceptions and inventory valuation; close the plan with an immutable summary.
14. **Follow-up** — repeated variances can trigger targeted counts, training, process review or loss-prevention investigation under separate controls.

## Count and variance rules

- A count plan has a stable ID, location scope, cutoff time, snapshot version and policy version.
- A count line identifies one canonical product/location/status (and serial for individually tracked devices).
- Blind counters cannot view expected quantity, average cost, variance or adjustment history unless separately authorized.
- A count snapshot must not change after the count begins.
- Count submissions are append-only. Corrections require a new count/recount record with reason.
- Expected quantity is snapshot quantity plus/minus valid ledger movements after the snapshot cutoff, using a consistent event watermark.
- A count cannot be finalized while in-scope movements are unaccounted for.
- A second count is required when configured variance thresholds are exceeded or serial-level reconciliation fails.
- For serialized products, every physical unit is individually scanned; aggregate quantity cannot substitute for serial identity.
- Quarantined, damaged, returned, display/demo, reserved and sellable quantities must be counted/reconciled as distinct statuses where policy requires.
- A count variance does not automatically imply a loss, theft, write-off or employee fault.
- An approved adjustment cannot exceed the variance supported by the approved count evidence without a separately documented exception.
- If stock changed after count cutoff, adjustment must be recalculated against the current balance under lock; stale count deltas must not blindly post.
- Cycle-count closeout is not a ledger posting. Only approved adjustment commands change physical stock.

## Adjustment reason taxonomy

Use controlled reason codes with a required explanation and evidence rules:

| Reason | Typical treatment | Required evidence |
|---|---|---|
| Count correction | Increase/decrease to reconcile verified physical count | Count plan, snapshot and count/recount evidence |
| Damage write-off | Reduce sellable/on-hand according to disposition | Inspection, photos and damage disposition |
| Loss / missing stock | Reduce quantity after investigation | Count history and investigation reference |
| Found stock | Increase quantity after identity and ownership validation | Product/serial validation and source/location evidence |
| Data correction | Correct known transaction or master-data error | Source transaction and correction explanation |
| Wrong location | Controlled transfer correction, not arbitrary gain/loss | Source/destination count evidence and linked transfer |
| Serial mismatch | Quarantine and resolve device identity | Serial scan, PO/receipt/sale history and inspection |
| Other | Exceptional adjustment | Manager-approved explanation and supporting evidence |

Wrong-location stock should normally use a linked transfer or transfer correction with paired legs, not an unpaired adjustment.

## Approval and valuation policy

- Requester and approver must be different active employees.
- Approval is based on trusted MME identity, permission, location scope and value threshold; client-supplied UUID or role is not authorization.
- High-value adjustments require second-level approval according to configurable policy.
- Damage/loss write-offs require evidence and disposition; high-risk or repeated variances route to Loss Prevention.
- Positive found-stock valuation must use verified cost evidence or a controlled finance-approved valuation decision.
- Negative adjustments relieve inventory at the approved carrying cost at posting time, under a locked balance version.
- Approval is tied to an immutable count/adjustment version. A changed quantity, product, location, reason or valuation invalidates prior approval.
- Posting must verify current stock, reservation and count cutoff under lock; if the expected balance changed, require recalculation/reapproval.
- Adjustments cannot reduce stock below reserved quantity or create negative on-hand/value unless an explicit policy exception is approved.
- Adjustment ledger events are immutable. Corrections use compensating events.

## Logical data model (subject to live-schema audit)

The following are logical entities, not claims that these tables already exist:

- **Count plan:** location/scope, schedule, owner, status, policy version.
- **Count snapshot:** immutable cutoff, ledger watermark, balance version and expected quantities by canonical product/location/status.
- **Count task:** assignment, zone/bin, counter, blind-count flag, status.
- **Count submission:** count quantity, status bucket, evidence, actor and timestamp; append-only.
- **Count serial observations:** protected serial/IMEI references for tracked products.
- **Recount:** independent second count linked to original count line.
- **Variance case:** expected, observed, adjusted expected, variance, classification, severity, investigation and disposition.
- **Adjustment request:** count/variance reference, canonical product/location, delta, reason, cost basis, status, requester and approval chain.
- **Ledger event:** one immutable, idempotent stock movement with unique source reference.
- **Count closeout:** summary, unresolved exceptions, ledger reconciliation and sign-off.

Do not create these as new production tables until the live schema is inspected for existing equivalent entities.

## Logical service boundary (not yet implemented)

- `POST /api/inventory/count-plans` — create count plan and scope.
- `POST /api/inventory/count-plans/:id/snapshot` — capture immutable ledger/balance cutoff.
- `POST /api/inventory/count-plans/:id/assignments` — assign count tasks.
- `POST /api/inventory/count-tasks/:id/submissions` — record a blind count.
- `POST /api/inventory/count-tasks/:id/recounts` — record independent recount.
- `POST /api/inventory/variance-cases/:id/investigation` — add findings and evidence.
- `POST /api/inventory/variance-cases/:id/adjustments` — create adjustment request.
- `POST /api/inventory/adjustments/:id/decision` — approve/reject under policy.
- `POST /api/inventory/adjustments/:id/post` — idempotently post approved adjustment.
- `POST /api/inventory/count-plans/:id/close` — close after all required reconciliation.
- `GET /api/inventory/count-plans/:id` — authorized plan and task view.
- `GET /api/inventory/variance-cases` — authorized variance queue.

All writes must validate on the server, derive actor identity from the authenticated session, enforce location/role scope, use idempotency for retryable operations and append audit/outbox records. These routes are logical contracts only.

## Security, audit and employee safeguards

- Separate count, recount, investigate, request-adjustment, approve-adjustment, post-adjustment and close-plan permissions.
- Counters cannot approve their own adjustments or view blind-count expected values.
- A manager cannot approve outside their location/value scope.
- Sensitive serial/IMEI evidence is protected and masked in general reports.
- Audit history records who counted, recounted, investigated, approved and posted, with timestamps and reasons.
- Preserve evidence and original count submissions; no destructive edits.
- Restrict access to loss-prevention case details to authorized personnel.
- Do not expose internal cost/value variance to customers or ordinary storefront APIs.
- No automated disciplinary action or employee-fault conclusion from a count variance.

## Mandatory tests

### Count integrity
- Snapshot is immutable and bound to a known ledger watermark.
- Blind count does not disclose expected quantity/cost to counter.
- Concurrent receipts/sales/transfers during count are reconciled using the cutoff watermark.
- Duplicate submissions and replayed requests do not create duplicate count observations.
- Count correction creates a new record; original count remains visible.
- Serialized count requires unique valid serials and reconciles to device registry.
- Recount is performed by a different authorized employee when policy requires it.

### Variance and approval
- Variance calculation includes valid post-snapshot movements exactly once.
- Unresolved timing differences block adjustment.
- Wrong-location variance routes to paired transfer workflow.
- Adjustment cannot exceed supported variance without approved exception.
- Requester cannot approve own adjustment.
- Unauthorized location/value scope, inactive user and client actor spoofing are denied.
- Changed request version invalidates prior approval.
- High-value adjustment triggers required additional approval.
- Negative stock, reserved-stock reduction and negative valuation are blocked.

### Ledger and reconciliation
- Approved adjustment posts exactly once despite retries/concurrent requests.
- Same idempotency key with changed payload conflicts.
- Same count variance cannot post through a second request under a different key.
- Ledger physical quantity reconciliation excludes reservation/release commitment events.
- Balance projection and ledger-derived quantity/value reconcile after posting.
- Count closeout cannot complete with unresolved blocking exceptions.
- Adjustment reversal is a compensating event and original ledger row remains immutable.

### Security and regression
- RLS, grants, function ownership/search_path, append-only audit and private evidence access pass.
- POS, receiving, transfers, reservations, returns, warehouse and inventory valuation regression tests pass.
- Migration replay and rollback tested on a disposable Supabase project.

## Release gates

1. Run the Build 011.01 read-only Supabase audit and verify live schema/migration history.
2. Identify existing cycle-count, stocktake, adjustment and variance entities before designing migrations.
3. Reconcile 009.59 adjustment tables/functions with canonical product/location/identity and Build 011.05 ledger semantics.
4. Correct reservation/release movement semantics before using ledger quantity sums for physical on-hand.
5. Design additive count workflow only where no equivalent live source exists.
6. Test snapshot cutoff, concurrency, approval thresholds, idempotency, valuation, RLS and rollback on disposable Supabase.
7. Run a shadow count/reconciliation before production activation.
8. Obtain explicit approval before production migration, merge or deployment.

No Vercel production deployment is required for this documentation-only stage. Do not change Vercel cron frequency or plan as part of this build.

## Acceptance checklist

- [x] Existing 009.59 adjustment request, approval and reconciliation functions inspected.
- [x] Existing self-approval and negative-stock controls identified.
- [x] Missing physical cycle-count workflow documented.
- [x] Blind count, snapshot cutoff, recount and variance investigation defined.
- [x] Adjustment reason, approval, valuation and posting controls defined.
- [x] Reservation-versus-physical-ledger reconciliation conflict identified.
- [x] Security and regression tests specified.
- [ ] Live Supabase schema and migration history verified.
- [ ] Existing count/stocktake entities identified.
- [ ] Canonical adjustment workflow selected and implemented.
- [ ] Cycle-count service/UI implemented.
- [ ] Disposable database and security/concurrency tests passed.
- [ ] Shadow count reconciled and production release approved.

## Completion status

Build 011.06's repository-level adjustment and cycle-count specification is documented. It does not claim that cycle counting, adjustment approvals or live reconciliation are currently operational. No database mutation, merge or production deployment is performed by this document.
