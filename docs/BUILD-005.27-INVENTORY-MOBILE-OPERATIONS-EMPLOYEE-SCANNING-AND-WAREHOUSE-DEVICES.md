# Build 005.27 — Inventory Mobile Operations, Employee Scanning, and Warehouse Devices

**Status:** Mobile workflow and device integration design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines secure mobile and tablet workflows for receiving, scanning, inspection, put-away, picking, packing, transfers, cycle counts, and store-floor inventory operations. No hardware has been purchased or connected, and no application code, database changes, tests, or deployments are included.

## 1. Purpose

Give authorized MME employees a consistent, fast inventory workflow on store tablets, phones, and warehouse scanning devices while preserving accurate stock identity, location, condition, custody, and audit history.

The mobile experience is a client of Inventory Core. It must not become an independent inventory ledger.

## 2. Ownership boundaries

- **Build 005 Inventory Core:** authoritative SKU/unit/lot identity, location, movements, holds, reservations, and availability.
- **Build 004 Identity:** actor, role, permission, and location scope.
- **Build 005.18:** barcode, QR, serial/IMEI, label, and scanning standards.
- **Build 005.17:** location and transfer workflows.
- **Build 005.19:** cycle counts and reconciliation.
- **Build 005.23:** returns, inspection, repair, and refurbishment.
- **Build 002:** POS and order fulfillment.
- **Device management / IT:** approved hardware, enrollment, configuration, updates, and remote access controls.

## 3. Supported device classes

Design for:
- employee smartphones with approved camera scanning;
- store tablets used by sales and operations;
- dedicated handheld barcode scanners;
- USB or Bluetooth scanners paired with approved tablets or workstations;
- warehouse workstations and label printers.

Hardware compatibility, operating-system versions, scanner protocols, printer models, and durability ratings must be validated before procurement or rollout. No device is certified by this document.

## 4. Mobile application experience

Provide role-appropriate workspaces:
- receiving and manifest review;
- scan-to-inspect;
- put-away and location lookup;
- item search and availability inquiry;
- pick, pack, and pickup staging;
- transfer dispatch and receipt;
- cycle count and recount;
- return intake and disposition;
- label printing and reprint requests;
- exception queue and task completion.

Show the employee's active location, current workflow, connection status, and last successful synchronization time. Restrict actions and data according to server-verified permissions.

## 5. Scan resolution and confirmation

A scan may resolve to a product, SKU, physical unit, serial/IMEI, barcode label, acquisition lot, order, or location. The application must identify which type was resolved before presenting an action.

- Detect ambiguous and duplicate matches.
- Confirm product, condition, and location before a stock-changing command.
- Mask sensitive identifiers except where the task requires authorized full access.
- Prevent a product barcode from being mistaken for a unique serialized-unit identifier.
- Provide manual lookup only with the same server-side validation as scanning.
- Require confirmation for destructive, irreversible, or high-impact actions.

## 6. Receiving workflow

1. Select an authorized inbound receipt or acquisition lot.
2. Scan the shipment, container, or expected manifest reference.
3. Scan each item or enter controlled quantity.
4. Resolve SKU and serialized-unit identity.
5. Record observed condition and required inspection.
6. Flag duplicates, missing manifest rows, overages, damage, and unknown items.
7. Submit the receipt for authoritative validation.
8. Print or reprint labels only after identity assignment is confirmed.

A successful scan is not proof of physical receipt until the receiving command is accepted and recorded by Inventory Core.

## 7. Put-away and location movement

- Scan the item or lot.
- Scan the destination location.
- Validate location type, status, capacity, and employee permission.
- Show the proposed movement before submission.
- Record accepted movement and custody event.
- Reject invalid or inactive locations.
- Do not treat a locally displayed destination as authoritative until the server confirms the movement.

## 8. Picking, packing, and pickup

- Load only an authorized order or fulfillment task.
- Scan the assigned SKU/unit and verify condition.
- For serialized goods, verify the exact unit against the order allocation.
- Record substitutions only through an approved order change.
- Confirm pack contents and packaging status.
- Move local pickup orders into pickup staging through an authorized movement.
- Record handoff or collection evidence under the applicable policy.

A shipping label or pick-list scan does not itself prove shipment or customer collection.

## 9. Transfers and cycle counts

### Transfers
- Scan transfer reference, source location, items, and destination.
- Record dispatch custody and quantities.
- At destination, scan actual received goods.
- Route shortages, overages, or identifier mismatches to discrepancy review.
- Do not close a transfer until required receipt/reconciliation steps are complete.

### Cycle counts
- Support blind, guided, serialized, location, and recount workflows.
- Record count session, assigned employee, location, and cutoff rules.
- Prevent duplicate scan counting within the same count session.
- Separate observed quantity from expected quantity.
- Submit variance for review; do not automatically adjust stock.

## 10. Connectivity and offline safeguards

Online mode is preferred for all stock-changing commands.

If connectivity is interrupted:
- show a prominent offline state and last sync time;
- allow only explicitly approved read-only or locally staged tasks;
- queue no privileged stock mutation for silent later execution;
- do not permit offline serialized-device sales or duplicate allocation;
- require server revalidation before any queued action is committed;
- surface conflicts for human review;
- preserve the original scan time and device/session reference.

Any offline command capability requires a separate threat review, approved scope, and conflict-resolution design.

## 11. Device security and management

Proposed controls:
- managed device enrollment and inventory;
- screen lock and supported device encryption;
- short idle lock for shared devices;
- individual employee sign-in and session expiry;
- role/location-based authorization;
- approved application distribution and updates;
- restricted local storage and clipboard use for sensitive data;
- secure transport and protected credentials;
- remote revoke/wipe through approved device management;
- lost/stolen device reporting and access revocation;
- scanner pairing controls and approved peripheral inventory.

Do not store service-role credentials, database passwords, or long-lived privileged tokens on client devices.

## 12. User experience and accessibility

- Large scan target and clear success/error feedback.
- Fast repeat-scan mode for high-volume receiving and counts.
- Haptic/audio feedback only where supported and configurable.
- Accessible labels, contrast, keyboard support, and scalable text.
- Clear distinction between scanned, validated, submitted, and committed.
- Safe retry behavior that does not duplicate movements.
- Tablet and phone layouts optimized for one-handed and gloved operation where practical.

## 13. Monitoring and audit

Capture:
- device enrollment and approved status;
- application version and sync state;
- actor and authorized location;
- scan resolution type and result;
- command correlation/idempotency reference;
- rejected commands and reason codes;
- offline conflict events;
- label print/reprint events;
- device loss, revocation, and security incidents.

Do not retain unnecessary raw camera frames or full serial/IMEI values in general telemetry.

## 14. Acceptance criteria

- [ ] Mobile clients use Inventory Core as the stock authority.
- [ ] Each scan resolves to an explicit identifier type.
- [ ] Ambiguous and duplicate scans are safely rejected or reviewed.
- [ ] Stock-changing actions require server-side authorization.
- [ ] Receiving, put-away, picking, transfer, and count workflows are supported by defined contracts.
- [ ] A scan is distinguished from a confirmed inventory transaction.
- [ ] Offline mode cannot silently commit stock mutations.
- [ ] Serialized devices cannot be double-allocated through mobile workflows.
- [ ] Sensitive identifiers and credentials are protected.
- [ ] Device loss supports session/access revocation.
- [ ] Retry behavior is idempotent.
- [ ] Tests cover duplicate scans, disconnected sessions, stale permissions, and device switching.

## 15. Completion boundary and next gate

This is a design specification only. No device was enrolled, paired, purchased, or tested. No scanner or printer integration was configured. No application code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve supported device classes, hardware shortlist, device management approach, offline policy, shared-device session rules, and mobile workflow priorities before implementation.
