# Build 001 — Inventory Transfer Recommendations

**Status:** Additive advisory function committed; not applied.

The trusted backend can query transfer candidates across active locations for aggregate (non-serialized) products. A source location must have available units above its configured target. A destination must have forecast replenishment need remaining after quantities committed on issued, acknowledged or partially received purchase orders.

Recommended quantity is capped at the lesser of source surplus and destination net need. The result includes both locations, stock/target levels, forecast daily demand, days of stock, confidence, unit cost and estimated transfer value.

The function is read-only decision support. It does not create a transfer request, approve a request, reserve stock or move inventory. An employee must submit a request and a different authorized approver must approve through the existing transfer workflow. Serialized units remain handled by the explicit-device transfer process and are not included in aggregate recommendations.

The forecast function's existing bounded result set and configured forecast rules apply. Recommendations are only as reliable as recorded sales, stock counts, targets and supplier commitments. The trusted API must enforce user role and location scope.