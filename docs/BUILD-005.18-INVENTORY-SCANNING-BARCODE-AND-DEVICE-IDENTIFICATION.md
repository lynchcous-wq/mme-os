# Build 005.18 — Inventory Scanning, Barcode, and Device Identification

**Status:** Design specification only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines barcode/QR scanning, SKU and serialized-device identification, scan workflows, label governance, and device integration boundaries. No application code, database objects, hardware integrations, tests, or deployments are implemented.

## 1. Purpose

Provide fast, reliable identification of MME products and physical inventory throughout receiving, inspection, storage, transfers, sales, returns, cycle counts, and fulfillment.

Scanning is an input and verification mechanism. It does not independently authorize inventory movements, sales, refunds, or account access. Inventory Core remains the authority for stock state and ledger movements.

## 2. Identification model

Keep these identifiers distinct:

- **Product/catalog ID:** Identifies the catalog product.
- **SKU:** Identifies the sellable product/variant and condition configuration.
- **Internal inventory unit ID:** Stable MME identifier for one serialized physical unit.
- **Serial number / IMEI:** Manufacturer or network identifier for a specific device; sensitive data.
- **Barcode value:** Encoded lookup value, which may represent an MME ID, SKU, or approved external identifier.
- **Lot/reference ID:** Identifies a quantity-controlled batch or acquisition lot.
- **Location/bin code:** Identifies a physical storage position.
- **Transfer/order/receipt ID:** Identifies an operational document or workflow.

A scan result must be interpreted by identifier type and context. Never assume every barcode is a SKU or every scanned number is a serial number.

## 3. Barcode and label standards

### 3.1 Label profile

Preserve the established MME barcode label preferences:
- Physical label: **2 × 3 inches**.
- MME logo: available as an optional uploaded logo from MME OS settings.
- QR code: disabled by default; enable only through an authorized label profile.
- Information density: **Automatic**.
- Standard “Much More Electronics” text: optional document/label format, not inserted into ordinary body text.

The label engine should support versioned profiles by use case, printer, and location.

### 3.2 Label content

A label may include, according to profile:
- MME inventory unit ID or SKU;
- concise product name;
- condition grade;
- storage location/bin;
- price only where an authorized price-label profile requests it;
- barcode symbology and encoded value;
- optional logo.

Do not print full IMEI, serial number, customer information, credentials, or sensitive account data on general-purpose labels.

### 3.3 Barcode and QR policy

- Select symbology based on scanner/printer compatibility and data length.
- Use internal opaque identifiers where practical.
- QR codes must resolve through an authenticated, permission-checked MME route; never embed secrets or unrestricted personal data.
- QR labels must not expose a public inventory record merely because someone can photograph the code.
- Validate encoded data length, character set, check digit where applicable, and scanner readability.
- Duplicate or malformed identifiers must be rejected or routed to controlled resolution.

## 4. Supported scan contexts

| Context | Expected behavior |
|---|---|
| Receiving | Match receipt line, SKU, unit, or lot; flag unexpected goods |
| Inspection | Open the correct unit/lot inspection record |
| Put-away | Verify item and destination bin before movement |
| Picking | Validate item against an authorized order/reservation |
| Packing | Confirm packed items against the shipment manifest |
| Transfer dispatch | Verify source items and transfer manifest |
| Transfer receipt | Match received goods to dispatched manifest |
| POS | Resolve item and validate current sale eligibility |
| Returns | Locate original sale/unit and start Build 017 inspection |
| Cycle count | Record observed item/quantity at the assigned location |
| Price labeling | Retrieve current authorized price and label profile |
| Demo/display | Identify display unit without treating it as ordinary sellable stock |

A scan must not bypass the workflow's approval, inspection, or authorization requirements.

## 5. Serialized-device identification

For serialized products such as phones, tablets, laptops, watches, and other supported electronics:

1. Resolve the internal inventory unit first when an MME label is present.
2. Capture external serial/IMEI only in a protected workflow when required.
3. Validate identifier format and duplicate assignment.
4. Check whether the identifier is already attached to another active unit.
5. Mask identifiers in ordinary screens, logs, alerts, and exports.
6. Restrict full-value access to specifically authorized roles and tasks.
7. Preserve a tamper-evident audit trail for identifier creation, correction, reassignment, and access.

IMEI/serial checks must not be represented as carrier, ownership, activation-lock, warranty, or blacklist verification unless the relevant authorized provider actually returned that result.

## 6. Quantity and lot scanning

For non-serialized inventory:
- Scan SKU and lot where available.
- Capture quantity with explicit unit of measure.
- Enforce positive quantities and available-balance limits.
- Support repeated scans with duplicate-scan protection.
- Require a count confirmation before posting bulk quantities.
- Keep lot, condition, and cost lineage intact.

Do not convert quantity-controlled stock into individually serialized units without an approved conversion workflow and audit evidence.

## 7. Scan workflow and user feedback

A scan interaction should show:
- recognized identifier type;
- matched product/unit/lot;
- condition and current workflow state;
- current location when authorized;
- requested next action;
- clear success, warning, or error feedback.

Provide distinct outcomes for:
- recognized and valid;
- recognized but wrong workflow;
- not found;
- duplicate;
- malformed;
- unauthorized;
- stale or already processed;
- network unavailable;
- ambiguous match requiring manual resolution.

Do not treat a successful scanner beep as confirmation that a database transaction committed. Show the authoritative server result.

## 8. Device and printer support

Design for:
- phone/tablet camera scanning;
- USB and Bluetooth handheld barcode scanners acting as keyboard input;
- supported mobile scanning devices;
- thermal label printers;
- receipt/label printer selection by workstation and location.

Device compatibility must be verified against actual models, operating systems, drivers, symbologies, and connection modes before procurement or production enablement. No specific hardware model is certified by this document.

Provide device registration, assignment, status, and support diagnostics without storing unnecessary personal device data.

## 9. Offline and network interruption behavior

- Clearly indicate when the client is offline or the server is unreachable.
- Do not represent queued scans as completed inventory transactions.
- If offline capture is approved later, store only the minimum encrypted pending command data.
- Revalidate actor authorization, workflow state, idempotency, and inventory availability when reconnecting.
- Reject or route stale/conflicting commands for review.
- Never replay a movement, sale, or receipt twice because a client retried after a timeout.

Offline transaction capability requires a separate security and conflict-resolution approval.

## 10. Duplicate and idempotency controls

Every mutating scan command should carry a unique idempotency key and workflow reference. The server must:
- return the prior result for an identical replay;
- reject reuse of a key with different command content;
- enforce uniqueness of protected identifiers;
- prevent concurrent scans from allocating the same serialized unit twice;
- retain enough audit context to investigate duplicate attempts.

## 11. Label generation and reprint governance

- Label generation must read current authorized product and inventory data.
- Label templates and profiles must be versioned.
- Price labels must show the effective price and, where required, timestamp/profile reference.
- Reprints must be logged with actor, reason, item/reference, printer, and profile version.
- Damaged or obsolete labels should be invalidated or replaced through an auditable process.
- A printed label does not itself create inventory or change stock state.

## 12. Permissions and audit

Proposed permission areas, to be mapped to Build 004:
- scan and resolve inventory;
- view masked device identifiers;
- view full serial/IMEI for approved tasks;
- create or correct identifier associations;
- generate and reprint labels;
- register/manage scanning devices and printers;
- perform receiving, picking, transfer, count, and POS scans.

Audit records should include actor, location, workflow, identifier type, protected reference, timestamp, result, device/workstation reference, and correlation/idempotency key. Avoid storing raw identifiers in general-purpose telemetry.

## 13. Integration boundaries

- **Build 001:** Website product display and customer-facing lookup; never expose internal stock identifiers.
- **Build 002:** Order and POS workflows request authoritative item validation.
- **Build 004:** Identity, role, permission, and actor authority.
- **Build 008:** Inventory operational workflows and warehouse UI ownership.
- **Build 017:** Returns inspection and disposition.
- **Build 022:** Document/contract references where scanning is part of an approved process.
- **Build 026:** Aggregated scan and workflow metrics, with sensitive identifiers excluded.
- **Build 005:** Authoritative SKU, unit, lot, location, movement, and reservation records.

## 14. Operational metrics

Proposed measures:
- scan success and failure rate;
- unrecognized and duplicate scan rate;
- scan-to-server-confirmation latency;
- receiving and picking scan accuracy;
- label reprint rate;
- identifier conflict rate;
- offline/retry volume;
- manual resolution rate;
- device/printer availability.

Metrics should be segmented by workflow and location without exposing serial/IMEI values.

## 15. Acceptance criteria

- [ ] Identifier types are distinct and interpreted by workflow context.
- [ ] The 2 × 3 inch label profile preserves the approved MME defaults.
- [ ] QR is disabled by default and any enabled QR route is authenticated.
- [ ] General labels and alerts do not expose full serial/IMEI.
- [ ] Serialized units cannot be duplicated or concurrently allocated.
- [ ] Quantity-lot scans preserve lot and unit-of-measure integrity.
- [ ] Scan feedback reflects the authoritative server result.
- [ ] Duplicate submissions are idempotent and conflicting key reuse is rejected.
- [ ] Offline scans are never shown as committed transactions.
- [ ] Reprints and identifier corrections are auditable.
- [ ] Device and printer compatibility is verified before production use.
- [ ] Tests cover malformed codes, duplicate scans, concurrent scans, permission boundaries, retries, and network loss.

## 16. Completion boundary and next gate

This is a design specification only. It does not implement scanning interfaces, generate labels, connect printers/scanners, validate live IMEIs, or change inventory records. No database inspection, migration, test, or deployment was performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Confirm supported scanner/printer models, approved QR use cases, label profile ownership, and which roles may view full serial/IMEI values before implementation.
