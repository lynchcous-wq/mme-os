# Build 001 — Inventory Lot & Landed-Cost Allocation

**Status:** Proposed additive migration; not applied.

## Receipt cost pool
A receipt can capture acquisition/pallet cost, freight, auction fees, handling and other documented costs. The pool total is the sum of those components and must reconcile to the acquisition line values supplied by the CEO or authorized buyer.

## Allocation
Additional costs are allocated by extended acquisition value (default) or equal per received unit. The final line receives any remaining cents so the complete cost pool is allocated without losing pennies. The resulting landed unit cost is passed to the existing aggregate receipt workflow, which updates weighted-average cost and writes inventory movement records in the same transaction.

## Controls
- Unique product/location lines and bounded quantities.
- Aggregate products only; serialized devices require their own unit-level landed-cost extension.
- USD cents; no floating-point money.
- Service-role RPC only; trusted server must verify actor, approval authority and location scope.
- Receipt, stock balance, weighted-average cost, movement and allocation records commit or roll back together.

## Limitations
This first extension does not yet provide auction CSV parsing, automated retail price research, per-unit serialized-device allocation, purchase-order matching, or accounting export. It does not change existing receipts or retroactively revalue stock.