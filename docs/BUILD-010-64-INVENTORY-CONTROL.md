# Build 010.64 — Inventory, Warehousing & Asset Control

## Implemented
- Multi-location register: store, warehouse, stockroom, in-transit, repair and quarantine.
- SKU master with reorder point, serial and IMEI tracking flags.
- Serialized asset registry with unique serial/IMEI and condition grades.
- Per-location stock balances with nonnegative and reservation constraints.
- Immutable-style stock movement ledger and audit events.
- Atomic stock receipt RPC with row lock, balance update, movement and audit in one transaction.
- Atomic stock reservation RPC with row lock and available quantity check.
- Atomic stock adjustment RPC with row lock and protection against negative or reserved stock.
- Transfer, cycle count, receipt, alert and reservation ledgers.
- Authenticated inventory API and dashboard.
- RLS and service-role-only grants; acceptance tests.

## Production blockers
- Transfer creation is metadata only; shipment, receipt, inter-location stock movement and in-transit reconciliation need atomic workflows.
- Cycle counts are register-only; line entry, independent approval, posting and variance adjustment are outstanding.
- Serialized receipt/transfer/sale/return flows need one atomic unit-level state transition. Serial registration is currently separate from quantity receipt.
- Low-stock alert generation, reorder automation, available-to-promise calculations, reservation expiry/release and sale fulfillment are not connected.
- Receipt RPC currently updates aggregate quantity; PO three-way matching and receipt-line detail are not integrated.
- Inventory valuation, FIFO/weighted-average costing, COGS, accounting journal integration, tax, bundles and landed cost are not implemented.
- Enforce item tracking flags against serial/IMEI input; verify actor role scopes, warehouse/store assignments and least privilege.
- Prevent duplicate receipt reference replay using idempotency keys and unique source constraints.
- Validate concurrent POS sale, reservation, receipt, return and transfer operations before go-live.

## Validation
Run `npm run test:build010:inventory-control`, existing POS/catalog/finance/security suites, `npm run lint` and `npm run build`. Tests not executed, migration not applied, not merged or production deployed.
