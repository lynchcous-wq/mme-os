# Build 001 — inventory forecasting and purchasing intelligence

**Status:** Proposed additive migration; not applied.

## Forecasting
The forecast uses paid order-line quantities at the product/location level over a configurable 7–365 day lookback. Average daily demand is sold units divided by the full lookback window, then multiplied by an explicit seasonal factor (0.25–4.0). Days of stock = available quantity / projected daily demand. Confidence is labeled from the number of distinct selling days, not presented as a statistical guarantee.

## Purchasing calculation
Suggested quantity = max(ceil(projected daily demand × (lead time + target coverage + safety stock)) − available quantity, 0). Estimated cash requirement = suggested quantity × current average unit cost. The figure is a planning estimate, not a supplier quote or landed-cost commitment. Serialized devices remain separate from aggregate demand calculations in this version.

## Seasonal controls
Seasonality is explicit and traceable as manual, prior-year, campaign, or event basis. The multiplier is not auto-inferred. The trusted server should require CEO approval for changes to the seasonal factor or forecast policy, and retain the source/basis in the rule.

## Purchase proposal workflow
Users with appropriate permissions can create a draft proposal with line quantities and estimated costs, then submit it. An authorized CEO approver can approve or reject with a note. Approval records intent only; it does not create a purchase order, send a supplier message, charge a card, or commit cash.

## Data limitations
- Only orders with status 'paid' count toward demand; partial refunds and returns are not yet netted from historical units.
- Forecasting uses the full lookback days as denominator, which is conservative for intermittent sellers.
- No stockout-censored demand correction or external market/seasonal feed is included.
- Proposal line cost is a snapshot supplied by the trusted service; it must be validated against approved vendor/landed-cost data before submission.
- Service-role-only functions must be called through the trusted server after employee/CEO authorization. Identity UUID parameters are audit attribution, not authorization.

## Verification
Apply migrations in order on a disposable Supabase database. Test zero demand, sparse demand, seasonality bounds, lead-time math, available-stock math, proposal totals, duplicate lines, submit/decision transitions, and concurrent updates. No production rollout is implied.
