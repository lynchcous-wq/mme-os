# Build 010.81 — Vendor Management & Supplier Performance

Status: implementation contract committed on an isolated feature branch. No live vendor master, onboarding portal, vendor scorecard, compliance workflow, or procurement integration is claimed to have been implemented.

## Audit findings

Repository searches on the Build 010.80 line did not locate verified vendor management, supplier onboarding, supplier performance, compliance document, or accounts-payable vendor runtime components. Build 010.80 defines a vendor/procurement master as a required authority but explicitly does not create a parallel vendor master. Build 008 also requires acquisition provenance, item-level cost evidence and approved financial controls.

Treat vendor management as a dependent module until the repository and connected runtime are audited for existing supplier records, finance/AP ownership, procurement interfaces, document storage and identity permissions. This contract does not establish that such services are absent from every connected environment.

## Objective

Provide a controlled lifecycle for approved suppliers and acquisition sources, from onboarding and due diligence through purchase activity, delivery performance, quality, financial reconciliation, review, suspension and offboarding.

Vendor management is the authoritative supplier relationship and qualification layer only if no existing enterprise vendor master owns those records. If an ERP, accounting, procurement or AP system is already authoritative, MME OS must integrate by stable external IDs and synchronization contracts rather than duplicate or override it.

## Ownership and integration boundaries

| Data / decision | System of record | MME vendor module behavior |
|---|---|---|
| Legal vendor identity and tax classification | Approved finance/vendor master | Reference and display authorized fields; do not create competing legal identity records |
| Vendor payment/banking instructions | Finance/AP provider | Never store or expose banking secrets in ordinary MME vendor screens |
| Vendor qualification and operational status | Procurement/vendor governance, if authoritative | Maintain qualification evidence or consume status through versioned integration |
| PO terms and approved commitments | Procurement | Link vendor to immutable PO revisions |
| Delivery/receipt outcomes | Receiving and Inventory | Consume accepted receipt evidence; do not rewrite receiving history |
| Product identity and catalog | Product Catalog | Map vendor part numbers to canonical product IDs through reviewed mappings |
| Acquisition source and landed cost | Acquisition/COGS and Accounting | Link provenance and approved cost evidence; do not set cost independently |
| Invoice approval/payment | AP/Finance | Show verified status only; never mark invoices paid from vendor communications |
| Employee permissions | Identity Matrix | Enforce server-side scoped permissions |

## Vendor lifecycle

Map these logical states to the canonical vendor status vocabulary after schema discovery:

1. Prospect — not approved for purchasing.
2. Onboarding — required identity and qualification evidence is being collected.
3. Pending review — submission complete and awaiting authorized review.
4. Approved — permitted for specified purchase categories, entities and locations.
5. Conditional — limited purchasing permitted under documented controls.
6. Suspended — new commitments blocked pending review; existing obligations remain visible.
7. Rejected — onboarding declined with controlled reason.
8. Offboarding — new commitments blocked while open orders, returns, invoices and claims are resolved.
9. Inactive — relationship closed; retained records remain available under retention policy.

Status transitions require an authorized actor, reason, timestamp, evidence and (where applicable) reviewer. Suspension or offboarding must not delete historical POs, receipts, invoices, warranties or acquisition evidence.

## Vendor profile contract

Use stable canonical vendor IDs and include only fields supported by the authoritative vendor master:

- Legal/trading name and approved aliases.
- External vendor ID and source system.
- Approved business address and delivery locations.
- Authorized operational contacts and role-based contact details.
- Approved product/category scope and MME purchasing entities.
- Onboarding/qualification status, effective dates and review date.
- Contract, terms, insurance and compliance evidence references.
- Approved PO communication method and vendor account reference.
- Vendor part-number/SKU mappings to canonical MME Product IDs.
- Operational notes with access controls and audit history.
- Related PO, receipt, invoice, return, warranty and claim references.
- Performance metrics with reporting period, source and calculation version.

Do not expose tax identifiers, banking details, personal contact details or confidential contract terms to users without explicit purpose-based permission. Keep sensitive documents in restricted storage and store references, not unrestricted file copies, in the profile.

## Onboarding and due diligence

1. Create a prospect or retrieve an existing vendor by stable legal identity/external ID.
2. Detect likely duplicates using normalized legal name, address and verified identifiers; do not auto-merge.
3. Collect only approved business and compliance information.
4. Validate required fields, file types, size, provenance and malware status for uploaded documents.
5. Capture evidence such as business registration, tax documentation, insurance, warranties, authorized contacts, product authenticity/chain-of-custody evidence and applicable certifications, according to vendor category and policy.
6. Route to designated procurement, finance, compliance or executive reviewers.
7. Record decisions, limitations, expiration dates, reviewer and reason.
8. Publish approved purchasing scope only after required reviews succeed.
9. Schedule renewal checks for expiring evidence and requalification.
10. Preserve a complete audit trail; changes to legal identity or payment instructions require independent verification through approved channels.

Do not treat possession of a document as proof of authenticity. Verification status, source and review date must be explicit.

## Vendor-to-catalog mapping

- Maintain vendor part numbers as vendor-specific identifiers.
- Map them to stable MME Product IDs and catalog versions.
- Support one-to-many and many-to-one mapping only when an authorized catalog owner approves the relationship.
- Record brand, model, configuration, capacity, region, condition and packaging differences.
- Prevent fuzzy title matching from silently selecting a different product variant.
- Require review for new, changed or conflicting mappings.
- Track mapping validity dates and source evidence.
- Do not let a vendor feed overwrite MME product descriptions, public pricing, specifications or images without the relevant catalog approval workflow.

## Purchasing and receiving integration

- Vendor approval status and category/location scope must be checked when a PO is created, approved and issued.
- Recheck vendor status before issuing a new PO; do not invalidate already accepted goods or erase obligations if the vendor is later suspended.
- PO vendor identity and terms are immutable per approved revision.
- Receiving must link to PO/vendor and preserve actual shipment and packing-slip evidence.
- Vendor performance uses accepted receipt events, not vendor-reported delivery claims alone.
- Substitutions, over-receipts, quality failures and short shipments create controlled exceptions.
- Acquisition lots and auction sources may be modeled as source relationships where they are not conventional suppliers; do not force an auction platform into the legal vendor identity record.
- Cost and landed-cost values remain owned by Acquisition/COGS and Accounting.

## Supplier performance scorecard

Show metrics with explicit period, sample size, source coverage and calculation version. A missing data source must display as unknown, not zero or a failing score.

Suggested metrics:

- On-time delivery rate, based on agreed delivery window and verified receipt timestamp.
- In-full delivery rate, based on accepted quantity versus confirmed PO quantity.
- Defect/inspection failure rate, based on completed inspection outcomes and eligible units.
- Substitution rate, based on authorized and unauthorized product substitutions.
- Invoice match rate, based on completed PO/receipt/invoice comparisons.
- Return/claim rate, with reason categories and denominators.
- Warranty claim response and resolution time, when supported by verified claim events.
- Document/compliance currency, based on current approved evidence.
- Price/terms variance, comparing invoice against approved PO revision.
- Responsiveness, only if objective timestamps and a defined measurement policy exist.

For each metric document numerator, denominator, exclusions, time window, source event and treatment of partial deliveries/canceled orders. Do not blend incomparable vendor categories into a misleading single ranking. If an aggregate score is requested later, publish its weighting, minimum sample size, confidence and review controls.

## Reviews, alerts and corrective actions

- Schedule periodic qualification reviews according to category risk and policy.
- Notify owners before required evidence expires.
- Alert on repeated delivery, quality, substitution or invoice discrepancies.
- Open a supplier corrective-action case for material recurring failures.
- Track issue, evidence, owner, target date, vendor response, containment, corrective action and effectiveness review.
- Escalate unresolved high-severity issues to procurement/operations leadership.
- Support conditional approval, purchase restrictions or suspension only through authorized approval.
- Deduplicate notifications and preserve the decision trail.
- Never automatically suspend a supplier solely from an unverified score or incomplete dataset.

## Search, reporting and access

- Search by canonical vendor ID, approved name/alias, external ID, PO reference and approved product mapping.
- Filter by lifecycle status, category, location/entity scope, review date, evidence expiry and performance period.
- Provide vendor profile, PO history, receiving outcomes, claims and scorecard drill-downs to authorized users.
- Export only permitted fields; mask restricted tax, bank, personal and contract data.
- Apply server-side role and entity/location scope on every query and mutation.
- Separate prospect creation, qualification review, purchasing approval, financial approval and payment administration.
- Require elevated permission for vendor status changes, legal identity changes, sensitive evidence access and vendor mapping approvals.
- Use audit logs for profile edits, evidence upload/access, status transitions, approvals, mapping changes, scorecard runs, corrective actions and offboarding.

Suggested role intent (not a claim that these role codes exist): procurement manages relationship and qualification; receiving records delivery evidence; catalog owners approve product mappings; finance/AP owns legal/tax/payment and invoice state; compliance reviews category-specific evidence; executives approve exceptions under delegated authority; IT administers technical access without business approval by default.

## Privacy, security and retention

- Verify vendor contacts and uploaded material as untrusted input.
- Scan uploads and restrict access through signed, short-lived access paths or equivalent controls.
- Encrypt sensitive fields and documents; keep secrets and payment instructions in their designated provider.
- Do not place bank account details, tax IDs, credentials or confidential documents in logs, analytics or broad exports.
- Record data source, verification status, access purpose and retention class.
- Apply retention and deletion rules that preserve legally required procurement, tax, warranty, dispute and audit records.
- Use least privilege, RLS and server-side authorization; never rely on UI hiding.
- Prevent cross-entity disclosure of confidential contracts and vendor pricing.

## Required tests

- Duplicate legal identity detection prompts review and does not auto-merge.
- Unapproved, rejected or suspended vendor cannot receive new PO commitments outside authorized exception policy.
- Existing accepted receipts and open obligations remain visible after suspension.
- Material vendor identity/payment instruction changes require independent verification and approval.
- Vendor part mapping cannot silently change canonical product identity or variant.
- PO vendor and approved terms remain tied to immutable PO revision.
- Scorecard calculations use verified events and show sample size/source coverage.
- Missing data displays unknown rather than zero.
- Canceled orders and partial receipts are treated according to documented metric definitions.
- Expired evidence triggers notification and review, not automatic unsupported suspension.
- Restricted tax, bank, personal and contract data is inaccessible to unauthorized roles and exports.
- Cross-entity/location access is denied.
- Audit records preserve actor, reviewer, source and timestamps.
- Customer/employee sign-in, catalog, PO, receiving, POS, warehouse and inventory reconciliation regression suites pass.

## Release gates

Do not mark Build 010.81 implemented or live until:

1. Existing ERP/accounting/AP/procurement vendor master ownership is identified.
2. Canonical vendor IDs, schemas, APIs and synchronization direction are verified.
3. Data classification, document retention and vendor verification policy are approved.
4. Vendor lifecycle and delegated approval matrix are approved by operations/finance/compliance.
5. Catalog mapping and receiving integrations are tested against real canonical records.
6. Scorecard formulas are validated with known PO, receipt, inspection and invoice fixtures.
7. RLS, sensitive data masking, audit, document access and segregation-of-duties tests pass.
8. Existing customer/employee sign-in and related catalog, POS, warehouse, receiving and inventory flows pass regression.
9. Staging data reconciliation confirms no duplicate supplier master or altered financial state.
10. Business owners approve monitored production rollout.

This contract does not authorize vendor approval, purchase commitment, payment instruction changes, invoice payment, supplier suspension, production data migration or deployment.
