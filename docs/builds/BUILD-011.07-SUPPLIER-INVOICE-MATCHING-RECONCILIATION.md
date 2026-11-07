# Master Build 011.07 — Supplier Invoice Matching & Reconciliation

Status: **repository-level specification committed; live AP authority, schema validation and runtime implementation pending**.
Branch: `implementation/build-011-purchasing-receiving-integration`.
Date: 2026-11-07.

## Objective

Establish a controlled supplier-invoice intake, matching and approval process that reconciles supplier billing to the approved purchase-order version and accepted goods/services evidence. Approved invoices may be handed to the canonical accounts-payable (AP) authority. This build does not initiate payments, mark invoices paid, or connect to bank, ACH or card execution.

## Existing implementation inspected

### Build 010.41 purchasing/vendor migration

Inspected `supabase/migrations/20261106002330_build010_purchasing_vendor_management.sql` on `implementation/build-010-41-enterprise-purchasing-vendor-management`.

It defines:
- `mme_vendors`, vendor contacts, purchase-order headers/lines and PO events.
- `mme_vendor_invoices` with vendor, optional PO, invoice number/date/due date, total, status and external reference.
- A uniqueness constraint on raw `(vendor_id, invoice_number)`.
- A direct PO receiving function that updates inventory balance and movement records.

The invoice register is not demonstrated to be a complete AP subledger. It has no invoice lines, approved PO version reference, receipt-line allocation, tax/freight/discount breakdown, normalized duplicate key, immutable document/version history, approval chain, credit-memo model or AP handoff state. Its `paid` status must not be interpreted as payment evidence or used to initiate/confirm payment. The direct PO receipt path remains a competing stock-mutation path and must be reconciled with the single receiving/ledger authority before production use.

### Build 009.58 receiving migration

Inspected `supabase/migrations/20261105001380_build009_receiving_inventory_intake.sql` on `implementation/build-009-58-receiving-inventory-intake`.

It defines staged receiving sessions/lines, serial capture, discrepancies, landed-cost entries and `mme_receiving_ap_matches`. The AP match is session-level and stores invoice amount, PO amount, received-goods amount, currency and a tolerance. It is useful as a receiving-side reconciliation record, but does not provide invoice-line-to-PO-line-to-accepted-receipt-line allocations or a complete invoice/AP lifecycle. Do not create a second authoritative invoice/AP ledger merely to extend this match table.

### Build 011.06 dependency

Build 011.06 defines the controlled inventory count/adjustment boundary. Invoice acceptance must consume accepted receiving evidence; invoice matching must never directly create or adjust physical inventory quantities.

## Canonical authority decision

Before schema work, inspect the live database and repository for an existing canonical AP invoice, supplier-credit, tax, legal-entity and accounting-period authority.

- If a canonical AP invoice authority exists, integrate through a versioned adapter and stable external IDs. Do not duplicate its invoice header, balance, payment state or posting journal.
- If none exists, propose an additive AP invoice domain only after finance/accounting ownership, legal entity, chart-of-accounts and posting requirements are confirmed.
- Keep the existing `mme_vendor_invoices` register as a legacy/source reference until records are reconciled and migrated. Do not silently repurpose or drop it.
- Treat invoice approval and AP acceptance as distinct states. AP acceptance is not payment.

## Invoice intake and evidence

Capture, at minimum:
- Canonical vendor ID and legal entity/business unit.
- Supplier invoice number as supplied and a normalized comparison key.
- Invoice date, received timestamp, due date, currency and supplier terms.
- PO ID and immutable approved PO version; allow an invoice without a PO only through an explicit non-PO policy.
- Invoice line descriptions, product/service references, quantities, unit prices and line totals.
- Tax jurisdiction/code/rate/amount, discounts, freight, duties, handling and other charges as separate components.
- Original document/evidence reference, file hash, source channel, uploader and verification status.
- Credit memo/debit note relationship, original invoice reference and reason when applicable.

OCR or document extraction may suggest field values but is untrusted input. A permitted employee must verify supplier identity, invoice number, currency, totals, PO references and tax/charge details against the source document before approval. Preserve original evidence and every corrected extraction/version.

## Duplicate detection

Use a normalized duplicate key scoped by legal entity and canonical vendor:
- Normalize Unicode consistently, trim whitespace, collapse internal whitespace and apply a documented case policy.
- Preserve the supplier's original invoice number separately.
- Normalize punctuation only under a documented vendor-safe policy; do not remove meaningful characters blindly.
- Enforce a unique key on (legal entity, vendor, normalized invoice number) for active financial documents.
- Also detect likely duplicates by document hash, amount/currency/date and supplier reference; fuzzy matches go to review rather than automatic rejection.
- Credit notes and debit notes must have distinct document types and cannot collide with the original invoice key.
- Concurrent intake must be protected by a database uniqueness constraint/transaction, not a client-side pre-check.

## Matching model

Perform line-level matching, not only header-total comparison.

1. **Vendor and entity** — invoice vendor must match the PO vendor and the purchasing legal entity. Any approved vendor substitution requires a documented amendment.
2. **PO version** — match only to the approved, immutable PO version effective for the order. A later edited draft must not rewrite the commercial terms used for matching.
3. **PO line** — map invoice line to canonical PO line/product/service, UOM, ordered quantity, unit price, currency and agreed terms.
4. **Accepted receipt** — allocate billed quantities to accepted receipt lines only. Exclude damaged, quarantined, rejected, missing and not-yet-received units unless an explicit policy exception applies.
5. **Quantity** — cumulative invoiced quantity across all invoices cannot exceed accepted quantity (or approved non-PO/advance policy). Support partial invoices and multiple receipts/invoices with allocation records that prevent overbilling under concurrency.
6. **Price** — compare invoice unit price and extensions to approved PO terms, including approved change orders. Apply configured tolerances only to eligible categories.
7. **Taxes and charges** — independently validate tax, freight, discounts, duties, handling and other charges against PO terms, receipts, supplier terms, jurisdiction and evidence.
8. **Currency/FX** — require invoice currency to match PO currency unless an approved contract permits otherwise. Record FX source, rate, timestamp and accounting currency conversion; never silently compare unlike currencies.
9. **Totals** — recompute line extensions, taxes and charges with a documented rounding policy and compare to invoice subtotal, tax total and gross total. Any unexplained arithmetic mismatch blocks approval.
10. **Landed cost** — pass eligible freight/duty/insurance/handling allocations to the inventory-costing authority as a separate, evidenced allocation. Do not conflate AP gross payable with inventory capitalization; tax recoverability and expense treatment belong to finance policy.

Support a clear match classification:
- **Two-way**: approved PO and invoice only, for policy-approved goods/services that do not require receipt evidence.
- **Three-way**: approved PO, accepted receipt and invoice; default for inventory goods.
- **Non-PO**: separately controlled expense invoice with budget/account coding and required approval; never silently bypass PO controls.

## Tolerances and exception handling

Tolerances are versioned policy, not hard-coded assumptions. Configure by legal entity, vendor/category, currency, tax/charge type and value band. Define both absolute and percentage thresholds, rounding rules and cumulative limits. A tolerance cannot override:
- Wrong vendor/legal entity or invalid PO status.
- Duplicate invoice.
- Unaccepted, rejected or quarantined quantity.
- Cumulative billing beyond accepted quantity.
- Unapproved PO price/version changes.
- Currency mismatch without approved FX terms.
- Missing mandatory evidence or invalid tax treatment.
- Segregation-of-duties or authority violations.

Create an exception case with category, severity, affected invoice/PO/receipt lines, expected and observed values, evidence, owner, due date, disposition, approver and immutable history. Categories include duplicate, vendor/entity mismatch, PO mismatch, quantity overbill, price variance, tax variance, freight/charge variance, FX variance, arithmetic mismatch, missing receipt, damaged/rejected goods, missing evidence and credit-note mismatch.

Possible resolutions: supplier corrected invoice, supplier credit, approved PO change order, accepted receipt correction, documented tolerance approval, non-PO reclassification where policy permits, or rejection. A waiver must record reason, evidence, policy authority and independent approver. No exception may be resolved by editing the original invoice evidence.

## Invoice lifecycle and AP handoff

Proposed state flow:
`received → extracting → verification_required → matching → exception / matched → approval_pending → approved → ap_handoff_pending → accepted_by_ap`.

Terminal or controlled alternatives include `rejected`, `voided`, `credited` and `superseded`. Payment status, if later supplied by the canonical AP/ERP authority, is read-only imported status and not an action in this build.

- Invoice versions and source documents are immutable. Corrections create a new version linked to the prior version.
- Approval is bound to exact invoice version, match result, PO version, receipt allocations, tolerance-policy version and coding.
- Any material change invalidates previous match and approval and reruns controls.
- Approval requires active trusted identity, specific permission, legal-entity/location scope and value threshold.
- Requester, invoice editor, matcher and approver roles are separated according to policy; no self-approval. High-value or exceptional invoices may require multiple approvers.
- Vendor onboarding or a general manager title alone does not grant invoice approval authority.
- AP handoff is idempotent and returns an external AP document ID, accepted/rejected status and error details. Retries with the same payload do not create a second AP invoice; changed payload under the same idempotency key conflicts.
- AP acceptance must reconcile the AP document ID and amount/currency before the invoice is considered handed off.
- No payment initiation, bank detail change, ACH/card instruction, payment release, cash application or paid-status mutation is permitted in this build.

## Logical data model (not a migration)

Subject to live-schema inspection, the required concepts are:
- Invoice header and immutable invoice versions.
- Invoice lines and charge/tax components.
- Source-document/evidence metadata and hashes.
- PO-version and PO-line references.
- Receipt-line allocation records with accepted quantity and cumulative billed quantity.
- Match run and per-line match results, policy version and computed totals.
- Duplicate-detection key and review cases.
- Discrepancy/exception case and resolution history.
- Approval requests/decisions and segregation-of-duties evidence.
- AP handoff/outbox record with external AP ID and idempotency key.
- Supplier credit/debit documents and links to original invoice/receipt/PO.
- Audit events and reconciliation reports.

These are logical entities only. Reuse canonical finance/AP and identity authorities where present; do not create duplicate vendor, PO, receipt, payment or accounting masters.

## API/service contracts (logical only)

- `POST /api/procurement/invoices/intake` — register evidence and invoice metadata.
- `POST /api/procurement/invoices/:id/versions` — add a corrected immutable version.
- `POST /api/procurement/invoices/:id/extract/verify` — verify extracted fields against source evidence.
- `POST /api/procurement/invoices/:id/match` — run line-level two-/three-way matching.
- `GET /api/procurement/invoices/:id/match` — view authorized match results.
- `GET /api/procurement/invoice-exceptions` — authorized discrepancy queue.
- `POST /api/procurement/invoice-exceptions/:id/resolve` — resolve with evidence and policy authority.
- `POST /api/procurement/invoices/:id/approval` — request approval for a specific immutable version.
- `POST /api/procurement/invoices/:id/decision` — approve/reject under permission and threshold policy.
- `POST /api/procurement/invoices/:id/ap-handoff` — idempotent handoff to canonical AP authority.
- `GET /api/procurement/invoices/:id/status` — read lifecycle and AP acceptance state.

All routes are proposed contracts, not implemented endpoints. Derive actor identity from the authenticated server session; never trust client-supplied actor UUID, role, approval limit or vendor identity.

## Security, privacy and audit

- Enforce RLS and server-side authorization by legal entity, location, vendor and permission.
- Use safe security-definer search paths and narrowly scoped function grants; no direct client write access to finance records.
- Protect tax IDs, bank details and confidential invoice attachments; bank-detail changes are outside this build and require a separate verified workflow.
- Store evidence in private object storage with signed, short-lived access and content hashes.
- Append immutable audit events for intake, version changes, extraction verification, match, exception, approval and AP handoff.
- Do not expose supplier costs, invoice documents, tax IDs or AP status to customer-facing endpoints or unauthorized employees.
- Use transactional locks/constraints for cumulative receipt allocations and duplicate checks.
- Use an outbox for reliable AP handoff; do not call external AP systems inside a database transaction.
- Keep logs free of full tax IDs, bank details, document contents and sensitive personal data.

## Mandatory tests

### Matching and accounting
- Exact two-way and three-way match; partial receipts; multiple invoices against one PO; multiple receipts against one invoice.
- Cumulative invoice quantity cannot exceed accepted quantity under concurrent requests.
- Rejected, damaged and quarantined quantities cannot be billed as accepted goods without approved exception.
- Wrong vendor, legal entity, PO version, product, UOM, currency and unit price are blocked or routed correctly.
- Price/tax/freight/discount/FX tolerances are versioned and applied only to permitted cases.
- Recomputed line, tax, charge and gross totals match the document within defined rounding policy.
- AP payable total and inventory landed-cost capitalization are reconciled separately.
- Credit memo/debit note linkage and supplier credit allocation work without rewriting original invoice.

### Duplicate, concurrency and idempotency
- Normalized duplicate invoice is blocked across case/spacing variants.
- Similar-but-not-identical invoice is flagged for review, not silently merged.
- Concurrent duplicate intake creates one canonical invoice.
- Concurrent invoice allocations cannot overbill accepted receipt quantities.
- AP handoff retry is idempotent; changed payload under same key conflicts.
- Duplicate external AP acknowledgement does not create duplicate handoff records.

### Approval, security and audit
- Requester/editor cannot approve own invoice.
- Approval requires active identity, correct entity scope, permission and threshold.
- Invoice version, PO version, match result or coding change invalidates approval.
- Unauthorized users cannot access invoice files, vendor financial data or exception evidence.
- Client actor/role spoofing is denied.
- Audit and invoice versions are append-only; evidence hash remains verifiable.
- RLS, grants, function ownership/search_path, storage policies and outbox retry behavior pass.

### Regression and operations
- Receiving, PO lifecycle, inventory ledger, landed-cost valuation, vendor master and finance/AP regression tests pass.
- Migration replay and rollback tested on a disposable Supabase project.
- Reconciliation report ties invoice totals to AP handoff records and separately to inventory cost allocations.
- Exception aging, due-date and duplicate dashboards reconcile to source records.

## Release gates

1. Complete the Build 011.01 read-only live Supabase schema and migration-history audit.
2. Identify canonical AP invoice, legal-entity, tax, accounting-period, credit memo and vendor authorities.
3. Reconcile 010.41 invoice register and 009.58 receiving AP match without creating competing financial masters.
4. Resolve competing PO receiving/inventory mutation paths and confirm accepted receipt evidence source.
5. Approve tolerance, tax, FX, landed-cost and approval-threshold policies with finance ownership.
6. Implement only additive adapters/tables where a canonical equivalent does not exist.
7. Test concurrency, RLS, idempotency, matching, accounting reconciliation and AP handoff in a disposable environment.
8. Run a shadow period and reconcile to finance/AP before production activation.
9. Obtain explicit approval before database migration, merge or production deployment.

No Vercel deployment is required for this documentation-only stage. Do not change cron frequency or Vercel plan as part of this build.

## Acceptance checklist

- [x] Existing 010.41 supplier invoice register inspected.
- [x] Existing 009.58 receiving-side AP match inspected.
- [x] Gaps between session-level amount match and line-level three-way match documented.
- [x] Duplicate invoice controls and immutable evidence/versioning defined.
- [x] Partial invoice/receipt allocation and cumulative overbilling controls defined.
- [x] Tax, freight, discounts, FX and landed-cost separation specified.
- [x] Exception workflow, approval segregation and AP handoff boundary specified.
- [x] Payment execution explicitly excluded.
- [x] Security, audit, concurrency and regression tests specified.
- [ ] Live AP authority and Supabase schema verified.
- [ ] Canonical AP integration selected and implemented.
- [ ] Disposable database/security/concurrency tests passed.
- [ ] Shadow reconciliation completed and production release approved.

## Completion status

Build 011.07 is a repository-level specification. No runtime invoice matching, AP integration, payment action, database migration, merge or production deployment is claimed or performed by this stage.
