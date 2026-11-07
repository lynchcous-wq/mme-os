# Build 010.80 — Purchase Orders, Receiving & Vendor Stock Intake

Status: implementation contract committed on an isolated feature branch. No purchase-order application, vendor master, receiving endpoint, inventory receipt RPC, database migration, or live stock intake is claimed to have been implemented.

## Audit findings and boundaries

The repository's Build 008 inventory specification explicitly describes itself as a specification, not proof of implementation. It defines product catalog, physical inventory units, acquisition/COGS, receiving/inspection, reservations, locations and inventory lifecycle as separate domains. It requires source provenance and item-level landed-cost allocation, and warns against treating a product model as a physical unit.

The inspected Supabase migration directory currently exposes a Build 010 warranty/security dashboard migration, not a verified procurement or inventory-receiving schema. Builds 010.77–010.79 document that canonical inventory tables, posting RPCs, and the actual POS/warehouse posting integrations still require discovery. No verified purchase-order or receiving runtime endpoint was found by the current repository search.

This build therefore defines the additive purchase-order and receiving contract. It must integrate with canonical Catalog, Acquisition/COGS, Inventory, Identity Matrix, Accounting and vendor records after those systems are inspected. Do not invent duplicate product, supplier, location, cost, employee, or inventory master records.

## Objective

Establish a controlled, auditable path from an approved purchase or acquisition through vendor delivery, receiving, inspection, item identification, cost evidence and inventory availability.

Receiving confirms custody and condition; it does not independently approve an acquisition, set selling prices, settle vendor invoices, or release every received unit as sellable stock.

## Domain ownership

| Capability | Authority | Receiving integration |
|---|---|---|
| Vendor identity and approved vendor status | Canonical vendor/procurement master, if present | Reference stable vendor ID; do not create a shadow vendor master |
| Purchase request and approval | Procurement / authorized approver | Consume approved request and budget/authority reference |
| Purchase order and amendments | Procurement | Source of ordered quantities, agreed terms and expected delivery |
| Auction/pallet acquisition and batch evidence | Acquisition/COGS | Link source lot, invoice/auction documents and item-level evidence |
| Product/model and specifications | Product Catalog | Resolve canonical product ID/version; do not create duplicate models |
| Physical unit identity and custody | Inventory Management | Create/resolve unit through canonical inventory intake workflow |
| Inspection and condition grade | Receiving / Quality / Returns policy | Record evidence and disposition before sellable release |
| Landed cost and valuation | Acquisition/COGS and Accounting policy | Consume approved cost records; never calculate a competing cost basis |
| Vendor invoice and accounts payable | Finance / AP | Match and route invoice evidence; receiving does not mark invoice paid |
| Stock movement and balances | Canonical Inventory ledger | Post accepted receipt exactly once through approved receipt operation |
| Employee authorization | Identity Matrix / permission service | Verify receiver, approver and location scope server-side |

If any named authority does not yet exist in runtime, record it as an implementation dependency; do not fabricate a parallel system of record.

## Purchase-order lifecycle

Use the existing procurement status model if one exists. Otherwise, the following are proposed logical states to map during schema discovery:

1. Draft — editable, not authorized for vendor commitment.
2. Pending approval — frozen snapshot submitted for approval.
3. Approved — approved scope, vendor, quantities, price/terms and budget reference.
4. Issued — transmitted to vendor with immutable PO version and delivery instructions.
5. Acknowledged — vendor confirmation and any variance captured.
6. Partially received — one or more receipts accepted; remaining quantities tracked.
7. Fully received — all eligible quantities received or explicitly dispositioned.
8. Closed — receiving and financial matching obligations completed or formally waived.
9. Canceled — only if policy allows and received quantities are handled through controlled disposition.

Changes after approval create a new PO revision with a diff, reason, actor and reapproval when material fields change. Never overwrite the originally approved terms. Prevent receiving against draft, canceled, or otherwise ineligible purchase orders.

## Purchase order data contract

The canonical PO record should reference, where supported:

- Stable PO ID, revision/version, legal entity and store/location.
- Vendor ID and verified vendor contact/delivery details.
- Requestor, approver, approval timestamp and authority/budget reference.
- Currency, payment terms, shipping terms and expected delivery window.
- Line-level canonical product ID/version, vendor SKU/part number, ordered quantity, unit of measure, agreed unit cost and tax/fee treatment.
- Expected serialized tracking requirements and condition/grade expectations.
- Source acquisition/auction lot and document references, where applicable.
- Delivery instructions, receiving location and permitted substitutions.
- Immutable approval/issue snapshot and correlation ID.

Validate quantity precision and unit of measure. Do not infer missing product identity or price from a fuzzy vendor description without review. Preserve vendor identifiers as references/attributes, not replacements for MME's stable product and unit IDs.

## Receiving workflow

### 1. Arrival and check-in

- Locate an issued/acknowledged PO or approved acquisition intake record.
- Verify vendor/carrier, delivery location, arrival time, packing slip and shipment/tracking references.
- Capture package count and visible damage before opening.
- Record receiver identity and device/time evidence under policy.
- Allow authorized blind receiving only if an explicit policy and variance controls exist.

### 2. Match and count

- Match delivered lines to PO lines using canonical product and approved vendor identifiers.
- Capture accepted, short, over, substituted and damaged quantities separately.
- Support partial deliveries and multiple receipts against one PO line.
- Prevent cumulative accepted quantity from exceeding the approved amount unless an authorized over-receipt tolerance/approval exists.
- Require an approved change or exception for substitutions; never silently map a different model or storage/RAM variant.
- Preserve packing-slip and source-document references.

### 3. Serialized electronics intake

For individually tracked products such as phones, tablets, laptops, watches and TVs where policy requires serial tracking:

- Scan or capture manufacturer serial/IMEI through a restricted intake control.
- Validate format and duplicate active-unit/custody conflicts against the canonical unit registry.
- Resolve or create the physical unit through the authoritative inventory service only.
- Bind unit to canonical product/version, acquisition source, PO/receipt, supplier, location and received condition.
- Encrypt restricted identifiers at rest and mask them in normal screens, exports, audit events and logs.
- Record missing, unreadable, duplicate, mismatched or activation/lock concerns as controlled exceptions.
- Never expose full IMEI/serial to public product pages or routine staff lists.

For quantity-tracked accessories, capture received quantity and approved SKU/unit-of-measure evidence without inventing serial requirements.

### 4. Inspection and disposition

Receiving and inspection are distinct from inventory availability. Support policy-driven inspection outcomes:

- Accepted — condition and identity satisfy release criteria.
- Inspection required — hold pending quality check.
- Quarantined — suspected fraud, activation lock, safety, identity, damage or documentation concern.
- Damaged — physical damage requiring approved repair, vendor claim or write-off decision.
- Rejected / return to vendor — controlled rejection with evidence and authorization.
- Short / missing — expected quantity not present.
- Substitution pending — delivered model differs from PO and requires approval.

Capture inspection checklist, grade, accessories, functional test evidence, photos/documents, reason codes, inspector and timestamp. Do not mark a device Available until all required inspection, identity, cost and approval prerequisites are satisfied.

### 5. Receipt posting

- The receiving workflow submits an approved receipt command to the canonical inventory posting service.
- The inventory ledger records one receipt movement for accepted quantity/units, linked to PO, receipt, line, location and source evidence.
- Use a stable idempotency key derived from receipt ID, line ID and accepted movement identity.
- Replaying the same command returns the original result; conflicting payloads are rejected.
- Record received-but-held units in the canonical incoming/inspection/quarantine semantics, not sellable available-to-promise.
- A scan, draft receipt or unapproved discrepancy does not mutate on-hand stock.
- Commit receipt and ledger movement atomically where possible; otherwise use a durable outbox with retry and reconciliation.
- Do not update stock balances directly from the browser or client device.

## Acquisition and landed-cost integration

- Link every receipt to its approved acquisition/COGS source where applicable.
- Preserve item-specific purchase cost and all approved freight, auction/buyer fees, taxes, handling and other landed-cost components.
- Use only approved allocation methods and versioned calculations.
- Preserve source inputs, allocation weights, formula, rounding rule, currency/rate source, unallocated residual and approval.
- Do not split a pallet total equally by default or invent item costs.
- Do not treat vendor invoice total as proof of payment.
- Do not derive selling price from cost or allow receiving to publish price changes.
- If cost evidence is missing or disputed, place the item in a policy-defined hold state; do not make it sellable if cost approval is a required gate.

## Vendor invoice and three-way match

Where the Finance/AP module is available, support matching of:
- Approved PO terms and quantities.
- Accepted receipt quantities and evidence.
- Vendor invoice line quantities, unit costs, taxes, freight and fees.

Route price, quantity, tax, freight, duplicate invoice and vendor identity mismatches to AP review with tolerances defined by finance policy. Receiving can submit evidence but cannot approve its own financial exception unless explicitly authorized by segregation-of-duties policy. Payment status comes only from the AP/payment authority.

## Exceptions and recovery

Create durable, auditable cases for:
- No matching PO or invalid PO state.
- Vendor or delivery location mismatch.
- Over-receipt, short receipt or duplicate delivery.
- Unauthorized substitution or price/terms variance.
- Duplicate, unreadable or conflicting serial/IMEI.
- Condition, damage, missing accessory or functional-test failure.
- Missing invoice, packing slip or cost provenance.
- Receipt posting timeout, duplicate request or ledger rejection.
- PO/receipt/invoice three-way match mismatch.
- Missing inspection, cost approval or required authorization.

Each case records stable ID, category, severity, PO/receipt/line/unit references, store/location, expected vs observed values, evidence, owner, age, state, resolution reason and actor history. Retrying a receipt uses the same idempotency identity. Correcting a posted receipt requires the canonical compensating movement workflow, never editing or deleting ledger history.

## Security, controls and audit

- Enforce server-side permissions for PO create/edit/approve/issue, receipt, inspection, cost review, invoice matching and exception resolution.
- Apply store/location scope on every request and database query.
- Separate requestor, approver, receiver, inspector and AP reviewer duties where policy requires.
- Do not rely on hidden UI controls as authorization.
- Keep service credentials server-side; never expose service-role keys to browsers.
- Validate uploads for size, type, encoding and malware; store source documents in restricted storage with retention controls.
- Treat vendor-provided text, barcodes, documents and URLs as untrusted input.
- Use safe output encoding and avoid executing uploaded content.
- Mask serial/IMEI, vendor banking details and other restricted data according to role.
- Audit PO revisions, approvals, vendor issue, receipt scans, quantity changes, inspection, receipt posting, retries, cost approvals, invoice matching and case closure.
- Preserve immutable source evidence and actor attribution.

## Required tests

- Draft/unapproved PO cannot be issued or received.
- PO approval snapshots are immutable; material edits require reapproval.
- Partial receipts reconcile across multiple deliveries.
- Over-receipt and substitution require configured authorization.
- Duplicate receipt submission creates one ledger movement.
- Same idempotency identity with changed payload is rejected.
- Serialized duplicate and custody checks prevent duplicate active units.
- Full serial/IMEI is not leaked through API responses, logs or exports.
- Inspection-required and quarantined units are not sellable/available.
- Accepted receipt posts once to the canonical ledger and correct location.
- A failed posting does not falsely mark the receipt posted or partially update stock.
- Outbox replay recovers transient failures without duplicate movement.
- Cost allocation preserves source evidence and approved method; no equal-pallet default.
- Three-way match flags PO/receipt/invoice variance and does not mark invoices paid.
- Unauthorized and cross-location users are denied.
- Segregation-of-duties checks prevent prohibited self-approval.
- Customer/employee sign-in, catalog, POS, warehouse, returns and inventory reconciliation regressions pass.

## Release gates

Do not mark Build 010.80 implemented or live until:

1. Canonical vendor, PO/procurement, receipt, product, inventory-unit, location, identity and acquisition/COGS schemas are inspected.
2. Existing source workflows and APIs are mapped; duplicate master data is ruled out.
3. Receiving and inspection state transitions are approved by operations.
4. Cost allocation and invoice matching rules are approved by finance.
5. Additive migration and authenticated server-side APIs are implemented against verified schema.
6. Receipt posting is integrated with the canonical inventory ledger and passes idempotency/concurrency/rollback tests.
7. RLS, permission scope, segregation-of-duties, document security and masking tests pass.
8. Customer/employee sign-in, catalog, POS, warehouse, returns and reconciliation regressions pass.
9. Staging receipts reconcile to ledger and PO balances with no unexplained variances.
10. Operations and finance approve controlled rollout and monitoring.

This contract does not authorize a vendor purchase, purchase-order issue, invoice payment, production stock receipt, cost approval, database migration, or deployment.
