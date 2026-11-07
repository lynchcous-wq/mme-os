# Build 010.82 — Inventory Transfers, Multi-Location Stock & Inter-Store Logistics

**Status:** Additive implementation contract committed on an isolated feature branch. This document does not claim runtime transfer workflows, inventory tables, APIs, migrations, or deployment.

## 1. Audit and design basis

Repository searches on the Build 010.81 line did not locate verified inventory-transfer, multi-location stock, store-location inventory, or dispatch/receipt runtime components. The canonical Build 008 inventory document explicitly states that it is a specification, not proof of implementation, and requires multiple locations and a controlled transfer lifecycle. Builds 010.75–010.80 likewise identify canonical inventory ledger, location, identity, and posting integrations as dependencies requiring verification.

Do not create a second product, inventory-unit, location, employee, or stock-balance master. Before runtime work, inspect the deployed Supabase schema, migrations, RLS policies, identity/location authorization model, canonical inventory ledger, and any existing store/warehouse/location master. Reconcile that evidence against this contract.

## 2. Objective

Provide controlled movement of quantity-tracked and serialized inventory between authorized MME locations (stores, warehouse, showroom, stockroom, receiving, inspection, quarantine, shipping staging, and pickup areas), with custody, quantities, evidence, approvals, and ledger postings traceable end to end.

## 3. Source-of-truth boundaries

| Domain | Authority | Transfer integration rule |
|---|---|---|
| Product/model | Canonical Catalog | Reference stable product ID/version; never duplicate catalog records |
| Physical unit / stock balance | Canonical Inventory ledger | Ledger is the authority for unit custody and stock quantities |
| Store/location | Existing canonical location master | Reference stable location IDs and hierarchy |
| Employee identity and permissions | Identity Matrix / permission service | Resolve actor server-side; enforce action and location scope |
| Dispatch/carrier evidence | Approved logistics/fulfillment service | Preserve shipment, handoff, tracking and proof references |
| Audit | Central audit service / immutable ledger | Preserve actor, event, reason, timestamp and correlation |

If an authority is not present in runtime, document it as a blocker. Do not fabricate a parallel system of record or assume a table/RPC name.

## 4. Transfer lifecycle

Required logical states:

1. **Draft** — editable request, no stock movement.
2. **Requested** — source, destination, item/quantity and reason submitted.
3. **Pending approval** — policy-based approval required; approval binds to the exact request revision.
4. **Approved** — eligible for source allocation.
5. **Allocated / Reserved** — source stock is reserved against the transfer and unavailable for other commitments; physical on-hand is not yet reduced unless the canonical ledger's reservation semantics explicitly require it.
6. **Dispatched / In transit** — confirmed handoff posts the source-side movement and records transfer-in-transit custody.
7. **Partially received** — accepted destination receipt for some units/quantity; remainder stays in transit or enters a documented exception.
8. **Received / Reconciliation required** — destination count and condition evidence recorded; discrepancies remain unresolved.
9. **Completed** — all expected quantities/serialized units reconciled and required ledger postings confirmed.
10. **Canceled** — only before dispatch, with reservation release; after dispatch, use a return/recall transfer or compensating movement, never erase history.

Every transition must validate current state, request revision, source/destination, actor authorization, quantity/unit, and required evidence.

## 5. Movement and quantity invariants

- Model source stock, reserved stock, transfer-in-transit, destination on-hand, and destination available-to-promise as distinct quantity classes.
- A transfer request, approval, pick, or scan does not by itself decrement on-hand.
- Dispatch moves the confirmed quantity into the canonical in-transit state exactly once.
- Dispatch alone never makes the quantity available at the destination.
- Destination on-hand/available increases only after an authorized receipt is confirmed and posted to the canonical ledger.
- Use paired, correlated source-dispatch and destination-receipt movements, linked to one stable transfer ID and line/unit identity.
- Use atomic ledger operations where supported. If cross-system atomicity is unavailable, use a durable outbox, retry policy, idempotency key, and reconciliation worker.
- Duplicate or replayed commands must not duplicate reservations, dispatches, receipts, or ledger movements.
- Corrections use authorized compensating movements; posted history is never silently edited or deleted.
- Quantity arithmetic must conserve stock across source, in-transit, destination, and explicitly approved loss/damage/write-off dispositions.

## 6. Serialized device custody

For serialized electronics, each unit must have one unambiguous custody/location state throughout dispatch and receipt. Validate serial/IMEI uniqueness using the approved restricted-identifier service; mask identifiers in ordinary screens and logs. Record the responsible handoff actor, timestamp, condition, packaging/seal evidence where configured, and destination acceptance. Do not expose full IMEI/serial values to unauthorized users or in customer-facing payloads.

## 7. Partial receipt and exception handling

Support:
- Full and partial receipt across multiple deliveries.
- Short, excess, substituted, unidentified, damaged, or missing units.
- Seal/package mismatch, wrong destination, failed scan, and carrier loss.
- Receipt posting timeout, duplicate submission, stale revision, and ledger rejection.
- Recall/return-to-source and transfer cancellation before dispatch.

Each exception records stable ID, transfer/line/unit references, expected versus observed quantity, source and destination, condition, evidence, owner, severity, age, state, resolution reason, approving actor, and complete history. Quarantined or disputed goods must not become available-to-promise. Excess receipt requires explicit configured approval; never silently accept it.

## 8. Authorization and controls

Enforce server-side:
- Create/request, approve, allocate, pick, dispatch, receive, inspect, reconcile, cancel, recall, and exception-close permissions.
- Source and destination location scope independently; cross-location users must not gain access merely by knowing a transfer ID.
- Separation of duties for approval and high-risk reconciliation where policy requires.
- Amount/quantity thresholds, restricted categories, high-value serialized devices, and location-specific operating hours/policies where configured.
- RLS and service-role isolation; no privileged credentials in browser code.
- Purpose-limited access to serial/IMEI and shipment/customer data.
- Immutable audit for every state transition, approval, scan, movement, retry, override, and evidence change.

## 9. User experience and reporting

Provide role-scoped views for:
- Transfer requests awaiting approval.
- Source allocation and pick/dispatch queues.
- In-transit shipments and aging transfers.
- Destination receiving and inspection.
- Discrepancy/exception work queue.
- Transfer detail timeline with actor, evidence, quantities and ledger references.

Reports distinguish requested, allocated, dispatched, in-transit, received, accepted, quarantined, missing, damaged, and completed quantities. Show source/destination location, aging, shipment reference, and reconciliation status. Never present in-transit quantity as available at either endpoint.

## 10. Automation and observability

Use durable, idempotent jobs/events for dispatch confirmation, carrier updates, receipt reminders, aging alerts, exception assignment/escalation, retry, and ledger reconciliation. Notification failure must not cancel or falsely complete a transfer. Every event carries stable event ID, transfer ID, correlation ID, minimal payload, and schema version. Track stuck transfers, duplicate/rejected commands, posting latency, unresolved discrepancies, and ledger imbalance.

## 11. Acceptance and regression tests

- Full transfer conserves quantity and creates exactly one dispatch and one receipt posting.
- Partial receipt leaves the remainder in transit and unavailable at destination.
- Dispatch does not increase destination availability.
- Duplicate/replayed dispatch and receipt commands are idempotent.
- Concurrent allocation cannot reserve more than source available quantity.
- Unauthorized source or destination users cannot view or mutate the transfer.
- Approval cannot be reused after request revision changes.
- Serialized units cannot be assigned to two active locations/custodians.
- Short, excess, damaged, missing, and substituted goods create exceptions and never silently adjust stock.
- Quarantined units are excluded from available-to-promise.
- Failed ledger posting remains recoverable and does not falsely mark a transfer complete.
- Compensating movements preserve original ledger history.
- RLS, API authorization, audit, and identifier-masking tests pass.
- Regression tests preserve existing customer sign-in, employee sign-in, catalog/product viewing, POS, warehouse, receiving, returns, and website behavior.

## 12. Runtime implementation gates

Do not mark this build implemented or live until:
1. Canonical product, inventory-unit, inventory-ledger, location, identity, audit, and logistics schemas are inspected in the target environment.
2. Existing location and inventory authorities are reused, with schema/RLS migration reviewed additively.
3. Transfer commands and read APIs are implemented server-side with scoped authorization and idempotency.
4. Ledger movements, reservation semantics, outbox/retry, and reconciliation are integrated and verified.
5. Transfer UI, receiving/exception workflows, and operational reporting are implemented.
6. Unit, integration, concurrency, security, RLS, and end-to-end tests pass.
7. Staging transfers reconcile to source, in-transit, destination, and exception balances with no unexplained variance.
8. Customer/employee sign-in and product catalog regression checks pass.
9. Production deployment and post-deploy smoke checks are recorded with exact commit and environment.

**Release note:** This contract is not a production migration, inventory adjustment, transfer authorization, or deployment approval. No runtime feature or production stock movement is claimed by this document.
