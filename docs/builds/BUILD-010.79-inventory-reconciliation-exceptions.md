# Build 010.79 — Inventory Reconciliation Dashboard & Exception Management

Status: operational design contract committed on an isolated feature branch. No live dashboard, inventory query, reconciliation worker, database migration, or production stock adjustment is claimed to have been implemented.

## Audit baseline

Build 010.77 documented that the inspected repository snapshot did not expose the canonical inventory schema or verified stock-posting RPC. Build 010.78 inspected the POS transaction creation route and confirmed that transaction creation is not proof of sale completion or inventory posting. The expected warehouse API route was not found at the inspected path, and the warehouse completion event was not verified.

The existing Build 010.73 warehouse dashboard specification describes pick waves, pick lists, barcode pick confirmation, packing verification, evidence references, discrepancies, fulfillment jobs and an inventory posting queue. It explicitly distinguishes pick activity from inventory deduction. This build must integrate with those canonical records only after their actual schema and endpoints are discovered.

Consequently, this build defines the reconciliation control plane and operational contract. It does not invent table names, database columns, permission names, balance calculations, or source status values.

## Objective

Give authorized operations, inventory control, store management and executive users a trustworthy view of inventory consistency across POS, warehouse fulfillment and the canonical inventory ledger. Surface mismatches as actionable, auditable exceptions without silently changing stock.

## Dashboard information architecture

### 1. Inventory health overview

Display only values derived from verified canonical data:

- Reconciliation coverage and last successful run.
- Pending, processing, posted, retryable and permanently rejected source postings.
- Aged pending events and retry backlog.
- Source-to-ledger quantity mismatches.
- Ledger-to-balance projection drift, if a canonical balance projection exists.
- Serialized-unit custody/location mismatches.
- Unresolved count variances and approved adjustments awaiting posting.
- Transfer dispatch/receipt mismatches and in-transit aging.
- Returns awaiting inspection/disposition.
- Failed or incomplete source references.

Every metric must show its source, as-of timestamp, store/location scope and freshness. If a source is unavailable or stale, show "unknown/stale" rather than zero.

### 2. Reconciliation work queue

Each discrepancy is a durable case with:

- Stable exception identifier.
- Exception category and severity.
- Store/location scope.
- Source workflow and source reference.
- Expected quantity/state and observed quantity/state, where both are verified.
- Related movement reference(s), if any.
- First-seen and last-updated timestamps.
- Current owner/team and SLA/aging state.
- Evidence links and correlation ID.
- Resolution status and reason.
- Actor, reviewer and approval history.

Sensitive serial/IMEI values must be masked. Do not put payment credentials or access tokens in evidence or logs.

### 3. Exception detail

Provide a chronological, append-only timeline showing source event, delivery attempts, inventory posting result, retries, reconciliation observations, assignment changes, approvals, compensating movements and closure.

Show the source system's state separately from the inventory ledger state. Never imply that one has been repaired merely because the other has changed.

### 4. Filters and drill-down

Support authorized filtering by store/location, date range, source system, event type, exception category, severity, owner and status. Search by safe source references and correlation IDs. Drill-down links must resolve to the canonical POS order/transaction, warehouse fulfillment, inventory movement, transfer, count or return record.

Do not expose cross-store data to users without explicit scope permission.

## Reconciliation rules

Reconciliation is a comparison and detection process, not a stock mutation process.

1. Compare only authoritative source records with canonical ledger postings.
2. Match source events using stable source references and idempotency identities.
3. Compare eligible quantities at the correct event milestone, not merely created, picked or packed quantities.
4. Respect partial fulfillment, split shipments, partial pickup, canceled orders and reservation releases.
5. Keep payment state distinct from order/sale state and inventory state.
6. Compare serialized-unit identity and custody using masked identifiers and canonical unit references.
7. Distinguish legitimate timing lag from permanent mismatch using documented event-age thresholds.
8. Account for late-arriving, replayed and out-of-order events without creating duplicate movements.
9. Do not treat an absent posting as proof that stock should be deducted; first verify source eligibility and canonical posting policy.
10. Do not infer inventory value from sales price or unapproved acquisition cost.
11. Record the reconciliation run version, input watermark, source coverage, result counts and errors.
12. If any required source is unavailable, mark the run incomplete and identify the missing source. Never publish a clean result from partial coverage.

## Exception categories

The following categories are logical classifications; map them to existing canonical enums if present rather than creating competing status vocabularies.

- Missing posting: eligible source event has no matching inventory movement after the permitted delivery window.
- Duplicate/conflicting posting: more than one movement or conflicting payload for one source identity.
- Quantity mismatch: eligible source quantity differs from posted quantity.
- Invalid source transition: posting references a source state that is not eligible.
- Reservation mismatch: source reservation is absent, expired, over-consumed or inconsistent.
- Serialized custody mismatch: unit identity, location or custody does not match source evidence.
- Location mismatch: source location and movement location disagree.
- Stale pending event: durable event has exceeded the configured processing window.
- Balance projection drift: canonical balance view differs from the sum/semantics of authoritative movements.
- Transfer mismatch: dispatch, in-transit and receipt quantities do not reconcile.
- Count variance: submitted count differs from expected stock and requires the count workflow's approval.
- Return disposition mismatch: returned goods are represented as sellable before authorized inspection/disposition.
- Source unavailable: required POS, warehouse, identity or inventory source could not be read.

## Case lifecycle and actions

All actions must be server-authorized and scoped to the relevant store/location.

- **Acknowledge / assign:** assign a responsible team or authorized employee; record actor and timestamp.
- **Request evidence:** request source documents or operational confirmation without altering inventory.
- **Retry posting:** only for a transient delivery failure, using the original stable idempotency identity and canonical posting API.
- **Reject / mark invalid:** only with a documented reason and authorized reviewer where required.
- **Approve correction:** route through the existing count, transfer, return, or inventory adjustment workflow. The dashboard itself must not invent an adjustment path.
- **Resolve:** close only after the source and ledger agree or an approved, traceable disposition is recorded.
- **Reopen:** preserve the previous resolution history and record the new evidence/reason.

No dashboard action may edit or delete immutable movement history. Corrections must use the canonical compensating movement process and approval policy.

## Automation and alerting

- Schedule reconciliation at a configurable cadence after source-of-truth and performance constraints are known.
- Trigger a targeted reconciliation after a durable posting failure, retry exhaustion, source completion, transfer receipt or approved count adjustment.
- Alert on critical aged pending events, duplicate/conflicting posting, cross-location custody mismatch and unexplained balance drift.
- Route alerts to the existing operations/IT task system if its integration is verified; otherwise retain an in-product queue and document the integration dependency.
- Deduplicate alerts by exception identity and escalation window.
- Include store, category, age, safe source reference and a secure dashboard link; omit sensitive device identifiers.
- Provide a daily summary with new, resolved, reopened and aging exceptions.
- Automation may detect, notify and retry safe idempotent operations; it may not approve adjustments or silently change stock.

## Access control and audit

Define access using the canonical MME Identity Matrix and permission service after inspection:

- Store associates: limited visibility and evidence submission for their authorized location.
- Inventory control: scoped reconciliation, case assignment and authorized retry.
- Store managers: location-scoped review and approval only where policy grants it.
- Operations/finance: broader reporting according to assigned permissions.
- IT/system operators: technical retry and diagnostics, not business approval by default.
- Executives: aggregated oversight and authorized drill-down.
- Customers: no access to internal reconciliation or exception records.

These are role intent descriptions, not a declaration that matching role codes or permissions already exist.

Enforce authorization on every server request and database query; UI hiding is not security. Apply RLS and least-privilege grants to any new persistence. Keep an append-only audit trail for case creation, assignment, status changes, retries, approvals, evidence access where required, resolution and reopening. Do not log service-role credentials, bearer tokens, full IMEI/serial values or payment card data.

## Operational and technical requirements

- Read from canonical source systems; do not create duplicate product, order, employee, location, serial, cost or inventory master tables.
- Use paginated, indexed, bounded queries and explicit date/location filters.
- Record run watermarks so interrupted runs can resume safely.
- Make reconciliation runs idempotent and safe to repeat.
- Keep dashboard reads separate from posting commands.
- Protect against stale writes with version checks on case transitions.
- Make retries bounded and observable; permanent validation and permission failures require human review.
- Preserve event and exception provenance.
- Provide export only for authorized, appropriately masked fields.
- Keep dashboard status truthful during source outages and partial runs.

## Required tests

- Correctly reconcile a sale that is completed and posted once.
- Flag an eligible sale with a missing posting after the defined grace period.
- Do not flag pick/pack-only events as missing stock deductions.
- Handle split shipments and partial pickup quantities.
- Detect duplicate source event identities and conflicting payloads.
- Retry transient failure with the same idempotency key and produce one movement.
- Do not retry permanent validation or permission failures indefinitely.
- Detect location, reservation and serialized custody mismatches.
- Detect incomplete source coverage and never report a false clean run.
- Preserve immutable movement history and require compensating movements for corrections.
- Enforce store/location and role access at the server/database layer.
- Mask serial/IMEI and exclude credentials/payment data from logs and exports.
- Preserve customer/employee sign-in, product catalog, POS, warehouse and returns regression.
- Verify dashboard freshness, pagination, query limits and accessibility.
- Verify alerts deduplicate and escalations follow configured thresholds.

## Release gates

Do not mark the dashboard live until:

1. Canonical inventory, POS, warehouse, identity and exception schemas are inspected.
2. Verified source APIs and posting references are mapped.
3. The reconciliation query is independently validated against known test fixtures.
4. Read-only shadow reconciliation completes with documented source coverage.
5. RLS, permissions, masking and audit tests pass.
6. Retry and case actions are proven idempotent and cannot bypass source approvals.
7. POS, warehouse, catalog, customer/employee sign-in and returns regression suites pass.
8. Operations owners approve thresholds, categories, routing and escalation policy.
9. Staging results reconcile without unexplained drift and production rollout is monitored.

This contract does not authorize production stock changes, exception auto-approval, database migration, or deployment.
