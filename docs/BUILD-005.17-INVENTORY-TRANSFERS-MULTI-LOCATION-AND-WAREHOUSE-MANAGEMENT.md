# Build 005.17 — Inventory Transfers, Multi-Location, and Warehouse Management

**Status:** Multi-location operations design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines location hierarchy, warehouse operations, inter-location transfers, custody, and multi-site inventory controls. No application code, database objects, hardware integrations, tests, or deployments are implemented.

## 1. Purpose

Support MME's current store and future warehouses or additional stores while maintaining one authoritative inventory ledger. Every item or quantity lot must have a known operational location or an explicit in-transit state.

## 2. Core principles

1. Every physical stock position belongs to one active location or an explicit in-transit custody state.
2. Location does not create a second inventory authority; Inventory Core remains authoritative.
3. Transfers are controlled workflows with dispatch and destination receipt evidence.
4. Source and destination permissions are independently checked.
5. A transfer does not make stock sellable at the destination before receipt and validation.
6. Serialized units retain their identity across all locations and movements.
7. Quantity lots must preserve SKU, condition, cost lineage, and unit of measure.
8. Unresolved discrepancies remain visible and are never silently balanced away.
9. Store-specific availability and reporting must respect location scope.
10. Multi-location rollout is staged and governed by explicit management approval.

## 3. Location hierarchy

Proposed hierarchy:
- company;
- region or operating area (optional);
- store or warehouse;
- operational zone;
- bin, shelf, cage, display, or other storage position.

Location types may include:
- retail sales floor;
- restricted stockroom;
- receiving area;
- inspection/quarantine area;
- repair/service area;
- shipping/dispatch staging;
- pickup staging;
- warehouse storage;
- in-transit custody.

Each location should have a stable ID, type, parent reference, active status, timezone, address/reference data, operating rules, and accountable manager. Do not use a display name as a stable identifier.

## 4. Location and access controls

- Users receive explicit location-scoped permissions through the identity authority.
- Source location authorization is required to initiate and dispatch a transfer.
- Destination authorization is required to receive and resolve a discrepancy.
- Cross-location supervisors may receive broader scope only through explicit grants.
- A user cannot grant themselves access by changing a UI selection or request payload.
- Inactive locations cannot receive new stock or reservations except through a controlled closure workflow.
- Location changes, closures, and permission changes require audit evidence.

Build 004 remains the identity authority. Its application-side session and actor integration is not verified complete; production location controls depend on that prerequisite.

## 5. Stock placement and custody

Inventory position must distinguish:
- received and awaiting put-away;
- available in a storage bin;
- available on sales floor;
- reserved;
- held or quarantined;
- allocated to an order;
- staged for pickup or dispatch;
- in transit;
- damaged or otherwise unavailable.

A location movement records source, destination, item/lot and quantity, actor, timestamp, reason, and correlation reference. For serialized units, retain the unit identity and lifecycle history. For quantity lots, prevent movement beyond the available lot balance.

## 6. Transfer lifecycle

Proposed states:
1. Draft
2. Submitted for approval (when policy requires)
3. Approved
4. Picking
5. Ready for dispatch
6. Dispatched / in transit
7. Partially received
8. Received
9. Discrepancy review
10. Closed or cancelled

Only permitted state transitions may be executed. A cancelled transfer after dispatch requires a controlled return/redirect process, not deletion.

### 6.1 Transfer request
Capture:
- transfer ID;
- source and destination;
- requested SKU/unit/lot and quantity;
- reason and priority;
- requested-by actor;
- required-by date;
- approval status;
- linked order or replenishment reference, if applicable.

### 6.2 Picking and dispatch
- Verify each serialized unit or counted quantity.
- Record picker and dispatcher where separation is required.
- Confirm source stock leaves the source's sellable balance at dispatch.
- Create an in-transit custody record.
- Generate a transfer manifest with protected identifiers masked by default.
- Do not treat a shipping label as proof of dispatch.

### 6.3 Destination receipt
- Verify manifest against physical goods.
- Record received, missing, excess, damaged, or unidentified quantities separately.
- For serialized units, verify identity and condition.
- Post accepted quantities to the destination only after authorized receipt.
- Route discrepancies to an assigned case and retain evidence.

Partial receipt must remain supported; the unreceived balance stays in transit or in an explicitly investigated state.

## 7. Transfer authorization policy

Management should configure approval thresholds based on:
- value or quantity;
- product category;
- condition or risk grade;
- source/destination combination;
- intercompany or third-party movement;
- exceptional or after-hours transfer.

High-value, restricted, or unusual transfers may require dual control. Approval thresholds and approver roles must be versioned and audited. This document does not set monetary thresholds.

## 8. Multi-location availability

Availability is computed by Inventory Core for a specified location and time. Views should distinguish:
- local sellable stock;
- local reserved/held/quarantined stock;
- incoming confirmed transfers;
- outgoing transfers;
- expected receipts;
- other locations' potential stock.

A website or POS must not promise another location's stock as available for immediate pickup without a valid reservation and approved fulfillment path.

Cross-location sourcing should show transfer time assumptions and must not silently reserve stock at another store.

## 9. Warehouse workflows

### Receiving
Receive against an approved acquisition/receipt reference, inspect, identify discrepancies, and stage for put-away.

### Put-away
Assign a valid destination bin/zone, verify capacity or handling constraints where modeled, and record the movement.

### Picking
Pick against an approved reservation or work order. Validate SKU, condition, unit identity, and quantity.

### Packing and dispatch
Verify packed goods against the manifest and move them into the correct dispatch/in-transit state.

### Cycle counting
Assign count scope by location/bin, freeze or control concurrent movements where necessary, record count evidence, and route variance for approval.

### Returns and quarantine
Use approved Build 017 disposition. Returned goods remain unavailable until the required inspection and stock transition is completed.

## 10. Location closure and relocation

Before closing or relocating a store/warehouse:
1. Stop new reservations and receipts according to approved cutover policy.
2. Identify open orders, holds, reservations, transfers, and in-transit stock.
3. Count and reconcile all physical inventory.
4. Transfer or disposition remaining stock with evidence.
5. Reconcile financial and operational balances.
6. Reassign staff and location permissions through Identity/HR.
7. Preserve historical location references; do not delete a location referenced by movements.
8. Obtain management sign-off before marking the location inactive.

## 11. Exceptions and alerts

Create assigned cases for:
- transfer overdue or missing;
- source/destination mismatch;
- partial receipt not resolved;
- damaged or unidentified goods;
- duplicate scan or identifier conflict;
- negative lot balance or impossible movement;
- stock found in an inactive location;
- location permission denial;
- in-transit custody record stale;
- repeated cycle-count variance.

Alerts should include severity, location, transfer reference, owner, due time, and next action. Do not expose raw serial/IMEI in ordinary notifications.

## 12. Reporting

Proposed dashboards:
- stock by store, warehouse, zone, and bin;
- available/reserved/held/in-transit quantities;
- transfer pipeline and aging;
- dispatch-to-receipt cycle time;
- transfer discrepancy rate;
- warehouse receiving and put-away throughput;
- pick accuracy and fulfillment exceptions;
- cycle-count completion and variance;
- stock concentration and cross-location replenishment opportunities.

Reports must identify data freshness and separate actual from expected/in-transit quantities.

## 13. Acceptance criteria

- [ ] Location hierarchy uses stable IDs and explicit location types.
- [ ] Each stock position has a valid location or in-transit custody state.
- [ ] Location permissions are enforced server-side.
- [ ] Transfer lifecycle and permitted transitions are documented and enforced.
- [ ] Dispatch and receipt are separate evidenced events.
- [ ] Partial receipt and discrepancy resolution are supported.
- [ ] Serialized identity and quantity-lot balances remain intact across transfers.
- [ ] In-transit stock is not represented as locally sellable.
- [ ] Cross-location availability is not a pickup promise without reservation.
- [ ] Location closure preserves history and resolves open stock obligations.
- [ ] Transfer and warehouse reports show freshness and unresolved exceptions.
- [ ] Non-production tests cover concurrency, partial receipt, duplicate scans, and authorization boundaries.

## 14. Completion boundary and next gate

This document is a design specification only. It does not create locations, transfer records, warehouse screens, scanning workflows, or hardware integrations. No database inspection, migration, test, or deployment was performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve location hierarchy, transfer approval thresholds, custody evidence, warehouse roles, and store-closure procedures before implementation.
