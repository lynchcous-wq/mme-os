# Build 010.72 — Supply Chain & Logistics Command Center

## Existing source-of-truth preserved
Extends existing MME procurement, purchase-order, inventory-location and inventory-transfer records. Does not create duplicate inventory balances, transfer ledgers, purchase orders or vendor masters.

## Added
- Shipment register for inbound, outbound, inter-store and return movements.
- Shipment source references, carrier name/service, tracking number/link, origin/destination, expected/actual delivery, package and declared-value metadata.
- Append-oriented shipment event history with timestamp, event type, location, carrier code and source reference.
- Delivery claims for lost, damaged, shortage, late and other exceptions.
- Authenticated API and logistics command-center dashboard.
- Shipment status transitions and integration with existing purchase-order, transfer and location lists.
- RLS and service-role-only direct table access.

## Important limits / release gates
- Carrier names and tracking details are manually entered. No carrier APIs, live tracking webhooks, label purchasing, rate shopping or carrier credentials are connected.
- Source record IDs are references for operator traceability; cross-module source validation and atomic synchronization with PO/transfer/order state are not implemented in this build.
- Shipment status PATCH is a privileged server-side update but does not yet enforce a complete transition graph or append a status event in the same database transaction. Do not treat it as a final production audit workflow.
- Claims are registered but no carrier claim submission, evidence vault, reimbursement receivable or automated resolution is implemented.
- No shipping label generation, package manifest, freight invoice reconciliation, or route optimization.
- Existing inventory transfer draft is not a shipment authorization; stock movement remains governed by the inventory transfer ledger.

## Validation
Run `npm run test:build010:logistics`, procurement, inventory, transfers, fulfillment and returns suites, `npm run lint` and `npm run build`. Tests not executed in this change. Migration not applied; not merged or deployed.
