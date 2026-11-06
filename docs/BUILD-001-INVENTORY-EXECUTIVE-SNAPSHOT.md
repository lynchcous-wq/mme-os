# Build 001 — Executive Inventory Control Center Snapshot

**Status:** Proposed additive migration; not applied.

## Unified location view
The executive snapshot returns one row per active store location, or one row for a selected active location. It combines catalog coverage, aggregate quantity and reservation totals, aggregate cost and retail value, serialized device counts and per-device landed-cost value.

## Command indicators
The snapshot also reports reorder alerts, products without configured reorder rules, open/critical inventory exceptions, open receiving sessions, active cycle-count sessions, pending purchase proposals, zero-cost aggregate units and below-cost aggregate SKUs.

## Accounting boundaries
- Aggregate inventory value uses the existing weighted-average unit cost.
- Serialized inventory value sums individual device landed costs for in-stock, reserved, repair and quarantine devices.
- Sold serialized devices are excluded from on-hand inventory asset value.
- Aggregate retail value is current catalog price multiplied by on-hand quantity; it is an opportunity indicator, not recognized revenue or a guaranteed sale value.
- Null monetary values indicate a supported-range overflow; the UI must show unavailable, never zero.

## Security and UI contract
The function is service-role only. The trusted API must verify CEO/executive/manager role and location scope before invoking it. The dashboard should provide location filters, KPI cards, separate aggregate/serialized panels, reorder and exception queues, receiving/count work queues, and drill-through to existing financial detail and movement history. This migration supplies the consolidated data contract, not a deployed front-end screen or live integration.

## Verification
The accompanying pgTAP test checks function existence, service-only access and dependencies. Full disposable-database tests must also verify location isolation, aggregate and serialized valuation, zero-cost flags, exception counts, and overflow behavior before merge.