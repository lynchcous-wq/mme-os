# Build 001 — Inventory Control Center KPI & Movement Feed

**Status:** Proposed additive migration; not applied.

The existing inventory dashboard and reorder intelligence migration already provides per-SKU/location rows, stock counts, aggregate inventory cost value and reorder recommendations. This extension adds a compact control-center KPI response and a searchable audit feed so the UI can display operational health without client-side aggregation.

## KPI summary
Location-filterable totals include active SKUs, aggregate on-hand/reserved/available units, aggregate inventory value at weighted average cost, serialized in-stock/reserved/sold/repair-or-quarantine counts, reorder alerts, products without reorder rules, open receiving sessions, open stocktakes and pending purchasing proposals. Serialized unit value is intentionally excluded until the unit-level landed-cost source is authoritative.

## Movement feed
The feed supports location, product, movement type and time-window filters with bounded pagination. Each row exposes before/after stock and reservation quantities, cost basis, receipt/transfer references, reason, actor and approver attribution. It is read-only and does not alter inventory.

## UI contract
The control center should show KPI tiles, low-stock/reorder queue, location/product filters, separate aggregate and serialized stock sections, open receiving/stocktake/proposal work queues, and a chronological movement table. Every value should retain its unit and currency; inventory cost value must not be labeled retail value, revenue or profit. Provide drill-through to the originating receipt, transfer, stocktake, purchase proposal or product record.

## Security and verification
Both RPCs are service-role only. The trusted application server must authorize CEO/manager/employee roles and location scope before invocation; never expose service-role credentials to the browser. Verify empty stores, multiple locations, serialized/aggregate separation, low-stock counts, pending-work counts, movement filters, stable ordering and pagination in a disposable database. This migration supplies data contracts, not the finished web UI or live deployment.
