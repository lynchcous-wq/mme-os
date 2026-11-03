# Build 001 — Inventory Financial Intelligence

**Status:** Proposed additive migration; not applied.

## Valuation
The summary reports aggregate units, weighted-average inventory cost value, current-price retail value, potential gross profit at current list price, weighted average cost and retail price, below-cost SKU count and units with zero recorded cost. Serialized units are excluded because the current serialized ledger does not yet establish authoritative per-unit landed cost.

## Product/location detail
Filter by store, category and SKU/title. Sort by inventory cost value, retail value, potential margin, oldest receipt event or SKU. Each row distinguishes on-hand, reserved and available units, weighted-average cost, current retail price, cost value, retail value and potential gross profit. A below-cost flag identifies current prices below weighted-average cost.

## Aging limitation
The oldest receipt timestamp is explicitly an event-history proxy only. It is not FIFO remaining-unit age, a lot-level aging schedule, or an accounting inventory-aging report. Exact aging requires receipt-layer allocation and depletion logic, which is a future extension.

## Financial controls
All amounts are integer USD cents. Cost value is not retail value, revenue, cash flow or profit. Potential gross profit assumes every on-hand unit sells at the current catalog price and excludes discounts, taxes, payment fees, shipping, returns, shrinkage and operating costs. Zero-cost units are flagged rather than silently treated as free inventory.

## Security and deployment
RPCs are service-role only. The trusted application server must authorize the actor and location scope. No browser service key. Migration and pgTAP test are committed as proposed code only; apply to a disposable database, validate queries and reconcile against accounting before production use.