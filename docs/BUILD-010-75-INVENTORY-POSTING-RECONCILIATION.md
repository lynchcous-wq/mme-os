# Build 010.75 — Automated Inventory Posting & Reconciliation

## Implemented
- Authoritative per-item/per-location stock balance table with nonnegative on-hand and reserved constraints.
- Inventory movement ledger with before/after quantities, source references, actor and unique idempotency key.
- Fulfillment posting RPC: locks job, queue and stock rows; validates available quantity; blocks serialized/IMEI-tracked items pending unit-level manifest; updates stock; records reservation consumption and movement; posts fulfillment state and event atomically.
- Failed posting is rolled back, marked failed/blocked with reason, and can be retried after correction. Posted jobs replay idempotently.
- Cycle-count sessions, count lines, submitted snapshots, controlled count posting, movement adjustments and reconciliation history.
- Serialized and IMEI-tracked SKUs are blocked from quantity-only cycle counts.
- Authenticated inventory operations API and reconciliation dashboard.
- RLS and service-role-only direct table access.

## Important boundaries
- No automatic queue worker or scheduled trigger is configured; an authorized inventory operator invokes the posting endpoint. Do not describe it as background automation.
- Stock balances begin at zero and require verified cycle counts to establish opening quantities. No opening stock is fabricated.
- Serialized/IMEI stock cannot be posted or cycle-counted until unit-level identity scanning and reconciliation are implemented.
- The posting operation uses available unreserved quantity; external reservations are protected. A job-specific reservation lifecycle and order cancellation release workflow require integration with the order system.
- Only customer-order fulfillment is accepted by this posting RPC. Transfers, returns and manual adjustments require dedicated ledger workflows.
- No website/POS availability event publisher or carrier handoff is enabled in this build.

## Validation
Run `npm run test:build010:inventory-posting-reconciliation`, warehouse, fulfillment, inventory, POS, returns and transfer suites, `npm run lint`, and `npm run build`. Tests not executed at PR creation. Migration not applied; not merged or deployed.
