# Build 001 — Markdown & Price Optimization

**Status:** Additive migration committed; not applied.

Creates a product-level markdown proposal queue. Initial conservative rules suggest 15% for no paid aggregate sales in 90 days, 10% for no paid sales in 60 days, or 5% when available-stock cover exceeds 90 days at the recent 30-day sales rate. A proposal requires available stock and a reliable weighted-average cost. Proposed price is floored at weighted-average cost; no below-cost markdown is proposed.

The proposal stores the current and suggested price, cost floor, rule, and evidence snapshot. A separate decision RPC supports rejection with a reason or approval by a different identity. Approval rechecks the current catalog price and weighted-average cost; stale proposals are marked stale. Only approval updates mme_products.unit_price_cents.

Pricing is product-global in the current catalog schema, not location-specific. The trusted API must authenticate and authorize CEO-level approval; identity UUID arguments are audit attribution, not proof of identity or role. This version excludes serialized devices and does not scrape competitor prices or automatically publish promotions.