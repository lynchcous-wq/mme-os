# Master Build 011.04 — Receiving Integration

Status: **repository-level receiving integration design committed; live schema and application implementation pending**.
Branch: `implementation/build-011-purchasing-receiving-integration`.
Date: 2026-11-07.

## Objective

Connect the single canonical purchase-order aggregate defined by Build 011.03 to controlled delivery intake, inspection, serial/IMEI capture, discrepancy resolution and the single inventory-ledger posting authority. Preserve the 009.58 and 009.59 work as implementation source material; do not create a second receiving or inventory posting system.

## Source code findings

### Build 009.58 — Receiving intake

The migration creates:
- Receiving sessions tied to `mme_procurement_purchase_order_drafts` and procurement requests.
- Receiving lines with physically received, accepted, damaged and missing quantities.
- Serial/IMEI/barcode capture, activation-lock status and device-test status.
- Receiving discrepancies, landed-cost evidence, intake staging, invoice match and audit records.
- Functions to open sessions, add lines, capture serials, add landed costs, finalize sessions and match invoices.

Important issues requiring correction before integration:
1. It is coupled to the 009.57 draft PO/request schema, not the formal PO aggregate described in 010.41 / Build 011.03.
2. It matches a received SKU to a single request-level `sku_reference`; it does not bind receipt lines to a stable formal PO line and canonical product ID.
3. `location_code` is free text rather than a validated canonical location ID.
4. The check constraint comparing received and missing quantity is tautological and does not enforce a meaningful invariant.
5. The line-add function checks over-receipt against one request's requested quantity, not remaining open quantity for a specific PO line across all receiving sessions.
6. The serial-capture function accepts a receiving-line ID without proving the line belongs to an open session, without enforcing accepted-unit count at capture time, and without server-derived actor identity.
7. The landed-cost function does not show session locking/state validation, currency allocation policy, or evidence requirements.
8. The finalization function allows session state `exception`; ledger posting later accepts both `reconciled` and `exception` sessions, relying on line-level open-discrepancy checks. The integrated workflow must make eligibility explicit and fail closed.
9. The invoice match computes accepted goods value for a session but does not demonstrate complete three-way matching by PO line, approved PO version, accepted receipt and invoice line.
10. The migration grants service-role access and enables RLS, but the live policies/grants and trusted service boundary still require verification.

### Build 009.59 — Inventory ledger receipt posting

The migration adds:
- Inventory balances and immutable ledger entries.
- Cost layers and adjustment/reconciliation records.
- `mme_inventory_post_receiving_intake`, an atomic-looking staged intake posting function with row/advisory locks, an idempotency key, discrepancy checks, serial validation and stock/cost updates.

Important issues requiring correction or validation:
1. It uses SKU text, location code and currency as the inventory identity, while the 010.41 model uses product ID and location ID. This must be reconciled to the canonical product/location model.
2. The posting function accepts a caller-supplied actor UUID; actor must instead be derived server-side from authenticated MME identity/permissions.
3. It allows posting when session status is either `reconciled` or `exception`. The target should allow only a finalized state with the relevant receipt line explicitly eligible and all blocking exceptions resolved or formally waived.
4. If an intake is already posted, the function returns a ledger entry by source intake ID without verifying that the repeated payload and idempotency key match the original command. Define replay semantics and reject changed payloads.
5. The ledger key incorporates a caller key but the source intake itself must also have a unique ledger-entry constraint to guarantee exactly one receipt posting per intake.
6. The serial check counts qualifying records but must also prove there are no duplicate, rejected, extra or cross-line device identifiers and that each accepted unit has exactly one valid device record when tracking is required.
7. The landed-cost allocation formula and currency consistency need explicit precision/rounding and reconciliation rules.
8. The function uses a balance keyed by SKU/location/currency; this must not be deployed beside another live product/location balance table.
9. The migration's grants, security-definer search_path, function ownership, RLS and audit protections need a database security review and runtime tests.

### Build 010.41 — Direct PO receipt

The formal PO migration defines `mme_purchase_order_receive_line`, which increments `mme_inventory_balances`, inserts `mme_inventory_movements`, updates PO received quantity and changes PO status in one function.

**This function is incompatible with the staged receiving-to-ledger route.** The integrated implementation must not execute this direct posting path in parallel with 009.58/009.59. Preserve the migration history, but route new receipts through the single controlled intake and ledger posting service after a reviewed cutover.

## Target receiving lifecycle

1. **Expected inbound** — formal PO is approved and submitted; line quantities, canonical product, location, currency and supplier commitment are frozen in an approved PO version.
2. **Arrival registered** — carrier, tracking, packing slip, appointment, arrival timestamp and receiving location are recorded.
3. **Session opened** — only for an approved, supplier-submitted/confirmed PO with remaining receivable quantity and authorized location.
4. **Line intake** — each line references a formal PO line ID and approved PO version; expected quantity is calculated from ordered minus previously accepted, rejected/cancelled and currently pending quantities under lock.
5. **Physical count** — capture physically received, accepted, damaged, rejected, missing and overage quantities; quantities must reconcile.
6. **Inspection** — record condition, functional test, accessory completeness, packaging, damage photos/evidence and disposition. Product-specific checklists are policy-driven.
7. **Serialized capture** — for tracked products, capture one unique serial/IMEI/barcode per accepted unit, validate format/duplicates, activation-lock status and test result. Do not expose full IMEI/serial in broad logs or analytics.
8. **Discrepancy workflow** — shortage, overage, wrong item, damage, serial mismatch, price variance or missing documents route to review. Blocking exceptions cannot post to available stock.
9. **Acceptance** — authorized receiver/inspector confirms accepted quantity and disposition. Separation of duties applies where policy requires independent approval.
10. **Staged intake** — eligible accepted quantity is staged with canonical product/location, source PO line/version, cost and currency snapshots.
11. **Ledger posting** — one idempotent inventory-ledger transaction posts accepted quantity, value, cost layer, intake state, PO received quantity projection and audit/outbox references atomically, or records a recoverable transaction outcome.
12. **Put-away / availability** — inventory becomes available only according to the warehouse put-away and inspection policy; quarantine stock is not available-to-promise.
13. **Reconciliation** — PO open quantity, accepted receipt, ledger quantity/value, balance projection and invoice match reconcile. Unresolved differences remain visible exceptions.

## Quantity invariants

For each PO line, quantities must be calculated across all sessions and receipt events, not per individual session only.

- Ordered quantity is fixed to a PO line version.
- Cancelled quantity is separately recorded and cannot exceed remaining open quantity.
- Pending physical intake is not accepted stock.
- Accepted quantity is bounded by inspected and approved physical quantity.
- Damaged/rejected/quarantined quantities are not available stock.
- Previously posted quantity is immutable except through a separate reversal/return process.
- Pending receipt reservations prevent concurrent sessions from accepting the same remaining PO quantity.
- Overages require an explicit supplier/manager exception and approved PO revision or separate authorized disposition; never silently increase ordered quantity.
- Partial receipt leaves a calculated outstanding quantity for later delivery.
- A PO is fully received only when every line's accepted/rejected/cancelled disposition is resolved under policy.

A reconciliation equation must be enforced per PO line and version:

`ordered = accepted + rejected_or_damaged + cancelled + outstanding`

Pending/in-progress physical counts are tracked separately until finalized; they must not be double-counted in the final equation.

## Target receiving data boundaries

| Record | Required key / link | Responsibility |
|---|---|---|
| Receiving session | PO ID, PO version, canonical location ID | Arrival and receiving work unit |
| Receiving line | Formal PO line ID, canonical product ID | Physical count and inspection outcome |
| Inspection evidence | Receiving line ID, evidence URI, checklist version | Condition/test proof |
| Serialized unit | Receiving line ID, canonical product ID, normalized serial/IMEI hash or protected value | Unique device identity and test state |
| Discrepancy | Session + optional line + type/severity/reason | Exception lifecycle and resolution |
| Intake staging | Receiving line ID, accepted quantity, cost snapshot, location ID | Eligible but not yet posted stock |
| Ledger entry | Unique source intake ID and idempotency command | Sole stock/value mutation authority |
| PO receipt projection | PO line ID, accepted ledger quantity | Derived/reconciled receipt progress |
| Audit/outbox | Actor, action, source, reason, correlation ID | Immutable audit and reliable downstream events |

Do not introduce a second balance table or movement journal. Select the live canonical inventory authority only after the Supabase audit.

## Required API/service boundary (logical, not yet implemented)

- `POST /api/procurement/purchase-orders/:poId/receiving-sessions` — open authorized receiving session.
- `POST /api/receiving/sessions/:sessionId/lines` — record physical line intake.
- `POST /api/receiving/lines/:lineId/inspection` — save checklist and evidence.
- `POST /api/receiving/lines/:lineId/serials` — capture tracked device identity.
- `POST /api/receiving/sessions/:sessionId/discrepancies` — create exception.
- `POST /api/receiving/discrepancies/:id/resolve` — resolve/waive with authority and reason.
- `POST /api/receiving/sessions/:sessionId/finalize` — reconcile physical counts and close intake.
- `POST /api/receiving/intakes/:intakeId/post` — invoke the sole authorized inventory posting command.
- `GET /api/receiving/sessions/:id` — permission-scoped session, lines, inspections and exceptions.
- `GET /api/procurement/purchase-orders/:poId/receiving-status` — outstanding and received quantities.

Every write must validate input server-side, derive actor from trusted session, enforce location and product permissions, use idempotency for retryable commands, and write audit/outbox events transactionally. These are proposed contracts; no deployed routes are claimed.

## Security and privacy controls

- Active employee/person identity and permission scope are resolved server-side.
- No client-provided actor UUID is trusted.
- Receiving staff can intake only at assigned/authorized locations.
- Separate receive, inspect, discrepancy-waive, ledger-post and inventory-adjust permissions.
- Serial/IMEI values are encrypted or otherwise protected at rest according to MME security policy; mask in UI, logs, notifications and analytics.
- Do not place customer device ownership, customer PII or activation credentials in supplier receiving records.
- Photos and documents use private object storage, short-lived signed access and malware/type/size validation.
- Security-definer functions use a fixed safe search_path, minimal grants and explicit ownership.
- Audit is append-only; corrections are compensating events, not destructive edits.

## Mandatory tests

### PO and quantity correctness
- Cannot open a session for unapproved/cancelled/closed PO or unauthorized location.
- Session line must reference a valid line and approved PO version.
- Multiple concurrent sessions cannot receive the same remaining PO quantity.
- Partial receipts across sessions reconcile exactly to line totals.
- Over-receipt is rejected unless an authorized exception and approved PO revision exists.
- Cancellation and supplier revision preserve earlier receipt history.

### Inspection and serial identity
- Wrong product, wrong SKU, wrong location and mismatched PO line are rejected.
- Required serial/IMEI count equals accepted tracked quantity.
- Duplicate serial/IMEI/barcode is rejected across all receiving sessions and inventory.
- Locked, failed-test, unknown or missing serial state cannot become available stock without explicit authorized disposition.
- Damaged/quarantined items cannot be posted as available inventory.

### Ledger correctness
- Exactly one ledger entry and balance update per accepted intake.
- Concurrent retries with the same idempotency key return the same result.
- Replayed command with altered payload conflicts.
- One intake cannot post twice under different idempotency keys.
- Ledger, balance, intake status, PO receipt projection and audit/outbox either commit together or roll back together.
- No PO or receiving endpoint directly writes a second inventory balance/movement authority.
- Cost layers, currency and landed-cost allocation reconcile to posted value.
- Reversal uses a separate compensating ledger event; no ledger deletion or mutation.

### Security and regression
- Inactive, customer, wrong-role and wrong-location actors are denied.
- Actor spoofing is impossible.
- RLS, grants, function search_path, private evidence storage and masking are verified.
- Existing POS, catalog, warehouse, purchasing, receiving, inventory and finance regressions pass.

## Implementation / release gates

1. Complete the live read-only Supabase schema and migration-history audit.
2. Confirm canonical PO line, product, location, inventory ledger, identity and audit sources.
3. Build a field-level crosswalk from 009.58/009.59 to the selected live sources.
4. Implement only additive compatibility and receiving changes on this Build 011 branch.
5. Ensure the direct 010.41 PO receipt function is not an active alternate posting path before cutover.
6. Replay ordered migrations on a disposable Supabase environment.
7. Run SQL invariants, RLS/grant tests, concurrency/idempotency tests and end-to-end receiving-to-ledger tests.
8. Open a reviewable PR and inspect Vercel preview only when an application code change requires it.
9. Do not apply production migrations, merge, or promote a deployment without explicit release approval.

## Acceptance checklist

- [x] 009.58 receiving migration inspected.
- [x] 009.59 ledger posting migration inspected.
- [x] 010.41 direct PO receipt path identified as conflicting alternate stock mutation.
- [x] Canonical PO-line receiving lifecycle defined.
- [x] Quantity, serial, inspection, discrepancy and ledger invariants specified.
- [x] Security, privacy and testing gates documented.
- [ ] Live Supabase schema and migration history verified.
- [ ] Canonical product/location/ledger sources selected.
- [ ] Receiving service and UI implemented.
- [ ] Disposable database and concurrency tests passed.
- [ ] End-to-end PO-to-receipt-to-ledger reconciliation passed.

## Completion status

Build 011.04's repository-level receiving integration contract is documented. Functional receiving implementation, live database validation and production readiness are **not** claimed. No database mutation, merge, or production deployment is performed by this document.
