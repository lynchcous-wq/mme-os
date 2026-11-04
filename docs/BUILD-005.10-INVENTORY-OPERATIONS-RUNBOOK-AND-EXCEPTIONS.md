# Build 005.10 — Inventory Operations Runbook and Exception Handling

**Status:** Operational design only  
**Branch:** `implementation/build-005-inventory-core`  
**Scope:** Defines proposed day-to-day inventory procedures, exception handling, escalation, and evidence standards. This document does not implement application workflows, change database state, run tests, or authorize production operations.

## 1. Purpose

Provide a consistent operating procedure for receiving, inspecting, storing, reserving, selling, transferring, adjusting, returning, and reconciling inventory at Much More Electronics (MME).

Inventory Core remains the authoritative source for inventory state, movement history, reservations, and availability. Employees must use approved application workflows rather than manually editing inventory records.

## 2. Operating principles

1. **Verify before action:** Confirm SKU, unit identifier, condition, location, quantity, and source document before posting a transaction.
2. **One authoritative record:** Use the approved Inventory Core workflow; do not maintain competing stock balances in spreadsheets or channel-specific systems.
3. **No silent corrections:** Correct errors through approved reversal/compensating transactions with a reason and evidence.
4. **Protect identifiers:** Show serial/IMEI data only to roles with a business need; mask it in general views, exports, notifications, and logs.
5. **Separate inventory from money:** Inventory movements do not themselves prove payment capture, refund, revenue recognition, or acquisition-cost approval.
6. **Use clear custody:** Every physical unit must have a known location or documented in-transit/exception state.
7. **Escalate discrepancies:** Never force a sale, invent stock, or reduce a balance to make a report match.

## 3. Role responsibilities

Final permissions must be mapped to Build 004 and approved by MME management.

| Role | Proposed operational responsibility |
|---|---|
| Receiving associate | Count deliveries, capture receipt evidence, identify discrepancies, submit receiving workflow |
| Inventory associate | Label, locate, move, and perform approved counts |
| Sales associate | View eligible availability, request reservation, complete sale through POS |
| Store manager | Review receiving exceptions, approve permitted adjustments/holds, manage location operations |
| Inventory manager | Reconcile stock, review transfers, oversee controlled adjustments and exception resolution |
| Returns specialist | Inspect returned items and submit disposition through Build 017 |
| Finance/COGS reviewer | Review acquisition documents and cost allocations in the designated finance workflow |
| IT/platform administrator | Maintain service availability and investigate technical failures without bypassing business approvals |
| CEO/authorized executive | Approve exceptional policy decisions and designated high-risk actions |

No role receives authority solely because a client sends a role name or employee title. Server-side permissions and location scope control access.

## 4. Standard operating procedures

### 4.1 Receiving a delivery

1. Confirm the expected purchase/auction/transfer reference and receiving location.
2. Compare package count and visible condition with carrier or supplier documents.
3. Photograph external damage and retain the relevant document reference.
4. Count each SKU separately; do not spread pallet cost evenly across unlike items by default.
5. Capture serial/IMEI identifiers for serialized products using the approved protected workflow.
6. Record quantity-based items as quantities, not invented individual serial units.
7. Place damaged, unidentified, or mismatched items into the designated receiving-exception/inspection state.
8. Submit the receipt and review the system confirmation.
9. Confirm receipt lines, stock created, and discrepancy quantities reconcile.
10. Escalate any mismatch before making affected stock sellable.

**Stop condition:** If the purchase reference, SKU, quantity, identity, or receiving location cannot be verified, do not finalize the receipt.

### 4.2 Inspection and condition grading

1. Confirm the unit is assigned to the correct SKU and inspection location.
2. Record the approved condition grade and required test results.
3. For electronics, follow the applicable product checklist (for example: power, display, battery, ports, cameras, connectivity, activation/lock status, and included accessories).
4. Record visible defects and evidence references.
5. Do not mark a unit sellable if a required test is missing or a lock/ownership issue is unresolved.
6. Submit the inspection and verify the allowed lifecycle transition.
7. Route return-related disposition decisions through Build 017.

### 4.3 Put-away and location changes

1. Verify destination location and access authority.
2. Scan or identify the correct SKU/unit.
3. Confirm the item is eligible to move and is not committed to another workflow.
4. Submit the transfer/movement through the approved workflow.
5. Confirm source and destination balances after completion.
6. Keep physical custody aligned with the recorded location.

**Stop condition:** Do not move an item physically while leaving its custody/location ambiguous. If the system is unavailable, use the approved downtime log and reconcile before sale.

### 4.4 Reservation and sale

1. Search the SKU and location using the approved POS workflow.
2. Treat displayed availability as informational until a reservation succeeds.
3. Request a reservation for the intended order.
4. Confirm the reservation reference and expiry.
5. Complete the sale through the approved POS/order process.
6. Confirm the inventory commit result before handing over the item.
7. For serialized products, verify the exact unit identifier against the item being handed to the customer.
8. If payment or order status is uncertain, stop fulfillment and escalate to the POS/Payments owner. Do not independently mark stock sold.

### 4.5 Holds and quarantine

Use a hold or quarantine state for suspected theft, damage, safety concerns, ownership/activation locks, disputed custody, or unresolved count differences.

1. Select the exact unit or quantity lot.
2. Choose the approved reason code.
3. Add concise supporting evidence.
4. Submit the hold through an authorized role.
5. Verify it is excluded from sellable availability.
6. Assign an owner and review deadline.
7. Release only after the reason is resolved and the release is authorized.

### 4.6 Transfers between locations

1. Confirm source, destination, item, and authorized transfer request.
2. Verify both locations are within the actor's approved authority.
3. Pack and identify the exact serialized units or quantity.
4. Submit the transfer.
5. Record carrier/custody details if the item is in transit.
6. Confirm destination receipt before treating the item as available at the destination.
7. Investigate any short shipment or damage as a transfer exception.

### 4.7 Cycle counts and reconciliation

1. Use an approved count scope and count window.
2. Avoid changing stock while a count is in progress unless the workflow explicitly supports controlled concurrent activity.
3. Count physical units independently from the expected system quantity.
4. Recount material discrepancies with a second authorized associate.
5. Compare SKU, serial/IMEI, location, condition, holds, reservations, and in-transit status.
6. Submit a discrepancy case; do not directly overwrite the balance.
7. Apply an adjustment only after required review and authorization.
8. Confirm the ledger, physical count, and availability projection reconcile.

### 4.8 Returns

1. Locate the original order/sale and item identity.
2. Route the return through Build 017.
3. Inspect and document the returned condition.
4. Wait for an approved disposition.
5. Only then submit the permitted inventory transition.
6. Keep refund/payment status in the payment/order system; an inventory disposition is not proof of a refund.

### 4.9 Downtime procedure

If Inventory Core or a required dependency is unavailable:

1. Stop inventory-changing actions that cannot be safely confirmed.
2. Do not use direct database edits, manual API calls, or alternate spreadsheets as a shadow stock ledger.
3. If management has approved a downtime log, record the timestamp, actor, location, SKU/unit, intended action, order/receipt reference, and evidence.
4. Mark each entry clearly as **pending system reconciliation**, not posted inventory.
5. Do not hand over stock if sale/commit status is uncertain.
6. After service recovery, an authorized operator enters each pending action through the normal workflow and checks for duplicate processing.
7. Close the downtime log only after all entries reconcile and a manager reviews exceptions.

## 5. Exception catalogue and response

| Exception | Immediate action | Required owner / resolution |
|---|---|---|
| Unknown SKU or identifier | Quarantine; do not create an improvised SKU | Catalog owner resolves mapping |
| Short/over shipment | Record actual count and evidence; leave discrepancy open | Receiving/inventory manager reconciles supplier record |
| Damaged on arrival | Hold affected stock; photograph damage | Inventory manager and acquisition owner determine disposition |
| Duplicate serial/IMEI | Stop receipt or sale of affected unit | Inventory manager investigates duplicate identity |
| Reservation conflict | Do not force checkout or allocate another unit silently | Inventory service/POS owner investigates conflict |
| Reservation expired | Recheck authoritative availability and create a new reservation if eligible | Sales associate follows normal POS flow |
| Sale/payment status uncertain | Stop handoff; do not mark sold manually | POS/Payments owner confirms authoritative order state |
| Transfer shortfall | Keep in-transit/discrepancy case open | Sending and receiving managers reconcile custody |
| Count mismatch | Recount and open discrepancy case | Inventory manager approves any adjustment |
| Suspected theft | Place approved hold and preserve evidence | Loss-prevention/manager workflow |
| Return condition disputed | Keep return under review | Build 017 returns owner decides disposition |
| Outbox/event delay | Do not manually replay business effects | IT/platform owner checks event status and idempotent replay |
| Protected identifier exposed | Limit further access and preserve incident evidence | Security/privacy incident process |
| Unauthorized stock change attempt | Do not retry with elevated credentials | Security and inventory manager review access |

## 6. Escalation and severity

- **P1 — Critical:** suspected unauthorized mutation, inventory data loss, duplicate sale/commit, overselling, identity bypass, protected-data exposure, or widespread inability to safely fulfill. Stop affected operations and notify the designated manager and IT/security owner immediately.
- **P2 — High:** location/ledger mismatch, failed transfer reconciliation, widespread reservation failure, or prolonged event backlog. Suspend affected workflow until controlled recovery is approved.
- **P3 — Medium:** isolated receiving/count discrepancy or recoverable workflow issue with stock safely held. Assign an owner and resolution deadline.
- **P4 — Low:** non-blocking display or usability issue with no stock, security, or financial integrity impact. Log for normal prioritization.

Incident severity and notification contacts must be configured by MME management before operational launch.

## 7. Required exception record

Each exception should capture:
- unique case/reference ID;
- opened time and reporting actor;
- store/location;
- affected SKU and protected unit reference (masked where appropriate);
- quantity and lifecycle state;
- related receipt/order/transfer/return reference;
- reason code and concise description;
- evidence links;
- immediate containment action;
- assigned owner and severity;
- approvals and compensating transactions;
- resolution, close time, and reviewer.

Do not place payment credentials, passwords, secret keys, or unnecessary personal data in the case record.

## 8. Daily and periodic control checklist

### Opening
- [ ] Confirm Inventory Core and POS availability.
- [ ] Review unresolved critical/high inventory exceptions.
- [ ] Review pending receiving, in-transit transfers, and expiring reservations.
- [ ] Confirm receiving and quarantine areas are access-controlled.

### During operations
- [ ] Use approved receiving, reservation, sale, transfer, and return workflows.
- [ ] Keep physical custody consistent with recorded location.
- [ ] Escalate uncertain payment/order state before handoff.
- [ ] Keep protected identifiers out of general notes and communications.

### Closing
- [ ] Review open receipts and transfer discrepancies.
- [ ] Review failed/expired reservations and unresolved holds.
- [ ] Review POS/inventory commit exceptions.
- [ ] Review outbox backlog and reconciliation alerts.
- [ ] Assign owners and deadlines to unresolved cases.

### Periodic
- [ ] Perform risk-based cycle counts.
- [ ] Review privileged access and location assignments.
- [ ] Review adjustment reasons and compensating movements.
- [ ] Test backup/recovery and downtime reconciliation procedures.
- [ ] Review exception trends and update training.

## 9. Training and authorization requirements

Before an employee performs an inventory-changing task:
- required training for the role is complete;
- Build 004 identity and server-side permission mapping is verified;
- location scope is assigned and tested;
- employee understands holds, quarantine, and escalation;
- employee understands that a displayed balance is not permission to bypass reservation/commit;
- supervisor approval is recorded where required.

Training completion does not itself grant technical permission.

## 10. Launch prerequisites

This runbook is not operational authorization. Before launch, MME must approve:
- role and permission matrix;
- location and custody procedures;
- condition grading and inspection checklists;
- exception severity contacts and response times;
- downtime log format and reconciliation owner;
- cycle-count frequency and adjustment approval thresholds;
- retention and access policy for evidence and protected identifiers;
- POS/payment handoff rules and return disposition ownership.

## 11. Completion boundary

This document is operational design only. It does not create UI workflows, employee permissions, automated alerts, forms, logs, or database records. It does not verify that any runbook procedure is currently available in the application.

**Next gate:** Review the operational procedures and launch prerequisites. Convert approved procedures into role-based application workflows only after the relevant identity, inventory, and service foundations are implemented and verified.
