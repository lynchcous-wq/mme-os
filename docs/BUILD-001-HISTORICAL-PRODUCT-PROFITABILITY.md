# Build 001 — Historical Product Profitability

**Status:** Additive migration committed; not applied.

Aggregate order lines now capture the location's weighted-average unit cost at line creation. The paid-product performance view compares paid line revenue with that historical cost snapshot, grouped by product, condition and location. It exposes paid units, paid order count, captured cost of goods, missing-cost units, gross profit and gross margin.

Important accounting boundary: this first view reports line revenue before order-level discounts, refunds, tax, payment processing fees and operating overhead. It must not be presented as final net profit. Lines without a reliable cost snapshot are disclosed and excluded from margin calculations rather than treated as zero cost. Serialized devices continue to use their separate per-device landed-cost and sale-outcome ledger.

Future reporting can add order discount/refund allocation, returns, markdown history, holding cost and sell-through windows after those source ledgers are verified.