# Build 010.74 — Inventory & Order Fulfillment Integration

## Implemented
- Fulfillment jobs linked one-to-one to warehouse pick waves.
- Fulfillment lines snapshot picked item, source location and verified quantity.
- Unique idempotency key prevents duplicate staging.
- Atomic staging function locks the wave and validates source identity, complete pick lines and package verification.
- Inventory posting queue with status, attempt count, error and movement-reference fields.
- Append-only-style fulfillment event history for staging and posting queue events.
- Authenticated warehouse API and dashboard read/stage integration.
- RLS and service-role-only direct table access.

## Critical release boundary
This build creates a controlled handoff to inventory posting. It DOES NOT deduct inventory, consume reservations, release unused reservations, change serial/IMEI status, or authorize carrier handoff. The queue is not yet consumed by an inventory worker. Before enabling production shipment, implement and verify a single database transaction that validates reservations and serialized assets, writes inventory movements/balance changes, marks the posting queue/job posted, and appends audit events. Do not manually mark jobs posted.

## Validation
Run `npm run test:build010:warehouse-fulfillment-integration`, warehouse, inventory ledger, reservation, transfer, returns, logistics and POS suites, `npm run lint`, and `npm run build`. Tests not executed in this change. Migration not applied; not merged or deployed.
