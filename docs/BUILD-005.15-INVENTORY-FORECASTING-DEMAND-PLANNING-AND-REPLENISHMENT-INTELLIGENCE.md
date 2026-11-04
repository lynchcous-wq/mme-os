# Build 005.15 — Inventory Forecasting, Demand Planning, and Replenishment Intelligence

**Status:** Forecasting and planning design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines demand signals, forecast methods, replenishment recommendations, scenario planning, and management controls for MME Inventory Core. No forecasting code, data pipelines, supplier integrations, purchase orders, database objects, tests, or deployments are implemented by this document.

## 1. Purpose

Help MME plan inventory purchases and store availability using transparent, explainable demand signals. Forecasts are decision support—not guaranteed sales, confirmed supplier stock, or permission to purchase.

The system must distinguish actual historical results from estimates, projections, and assumptions.

## 2. Principles

1. Use verified sales and movement history where available; label missing or incomplete history.
2. Separate demand from stock availability, lost sales, returns, transfers, and reservations.
3. Forecast at the appropriate SKU, product family, and location level.
4. Show assumptions, confidence, data freshness, and forecast horizon.
5. Avoid false precision for new products or sparse history.
6. Keep supplier lead times and minimum order quantities as sourced, dated inputs.
7. Recommendations never create purchase commitments without authorized approval.
8. Preserve human overrides with reason, owner, and audit history.
9. Prevent duplicate demand counting across website, POS, auction, and other channels.
10. Do not treat a product view, cart addition, bid, or reservation as a completed sale.

## 3. Data inputs and source ownership

| Input | Source owner | Planning use |
|---|---|---|
| Completed sales and quantities | POS / order domain | Primary demand signal |
| Cancelled orders and failed reservations | Order / inventory workflow | Separate unmet or uncompleted demand |
| Returns and refunds | Build 017 / payment and order domains | Net demand and return-rate context |
| Current sellable stock | Inventory Core | Available supply |
| Holds, quarantine, and reservations | Inventory Core | Exclude unavailable stock |
| In-transit quantities | Transfer / fulfillment workflow | Expected supply, with confidence |
| Supplier lead time and MOQ | Acquisition / supplier records | Replenishment timing and constraints |
| Item-level landed cost | Acquisition / COGS | Cash and margin planning |
| Retail price and promotions | Pricing | Explain demand changes |
| Channel and location | POS / website / auction | Demand segmentation |
| Seasonality and events | Approved planning inputs | Contextual adjustment, not assumed fact |

Every input must include source, as-of time, and quality status. If actual historical data is unavailable, the dashboard must not fabricate it.

## 4. Forecast dimensions

Support planning by:
- SKU and product family;
- store/location;
- channel (POS, website, auction, other approved channels);
- condition grade (new, refurbished, used, open-box, or approved taxonomy);
- time horizon (short, medium, and long planning windows);
- units and value, shown separately.

Serialized devices should be planned at SKU/condition level for demand; individual serial/IMEI values are not forecasting dimensions.

## 5. Forecast methods

Select method based on data sufficiency and category behavior:

### 5.1 Baseline methods
- Recent average sales rate for stable, sufficiently observed items.
- Weighted moving average to emphasize recent demand.
- Seasonal comparison only when enough comparable periods exist.
- Intermittent-demand method for low-frequency products.
- New-item analog forecast using a clearly named comparable group and explicit confidence penalty.

### 5.2 Adjustments
Allow authorized planners to model:
- approved promotions and price changes;
- seasonality and holidays;
- launch or discontinuation;
- known supplier constraints;
- channel shifts;
- store opening or closure;
- one-time events and exceptional demand.

Each adjustment must record who made it, why, when, and which forecast version it affected.

### 5.3 Forecast quality
Report:
- forecast horizon and generation time;
- method and input window;
- actual units versus forecast units when actuals become available;
- error measures appropriate to the data volume;
- bias (systematic over- or under-forecast);
- confidence band or qualitative confidence level;
- data completeness warnings.

Do not show confidence percentages unless calibrated and validated on historical data.

## 6. Inventory position and reorder calculation

Planning must distinguish:
- on-hand physical quantity;
- sellable quantity;
- reserved quantity;
- held or quarantined quantity;
- in-transit quantity;
- expected receipts;
- forecast demand during lead time;
- safety-stock target;
- proposed replenishment quantity.

A conceptual inventory position is:

    sellable on-hand
    + eligible confirmed inbound
    - committed reservations
    - other approved demand commitments

The exact formula must be reconciled with the Inventory Core availability model to avoid double subtraction.

A reorder recommendation may consider:

    demand during replenishment lead time
    + approved safety stock
    - eligible inventory position

This is a planning model, not an executable purchasing formula. MOQ, pack size, budget, supplier constraints, and approval policy must be applied before a proposed quantity is shown as actionable.

## 7. Recommendation categories

- **Reorder soon:** forecast inventory position may fall below approved target within lead time.
- **Stockout risk:** projected sellable availability may reach zero before replenishment.
- **Excess / slow-moving:** projected supply materially exceeds forecast demand.
- **New-item watch:** insufficient history; use conservative review rather than automated reorder.
- **Supplier delay risk:** expected inbound timing is stale or disputed.
- **Data quality warning:** incomplete sales, inventory, or lead-time data makes the recommendation unreliable.

Each recommendation includes SKU, location, suggested quantity or review action, supporting assumptions, forecast horizon, source timestamp, confidence, and assigned planner.

## 8. Scenario planning

Authorized managers may compare scenarios such as:
- base demand;
- higher/lower demand;
- supplier lead-time extension;
- promotion uplift;
- reduced purchasing budget;
- store-level transfer alternative;
- product discontinuation.

Scenarios are isolated from actual inventory and orders. They must never reserve stock, alter prices, create purchase orders, or change the official forecast until an authorized planner publishes a reviewed version.

## 9. Budget and cash planning

Planning views may estimate:
- proposed units;
- estimated item-level landed cost;
- total proposed acquisition cash requirement;
- expected weeks of supply;
- projected aging/excess exposure;
- estimated margin context using approved price/cost data.

Show actual cost separately from estimated cost. Restrict cost and margin views to authorized roles. Do not imply that a forecasted sale or margin is realized revenue or profit.

## 10. Human review and purchasing boundary

Recommended workflow:
1. Generate forecast and recommendation.
2. Validate data freshness and inventory position.
3. Planner reviews SKU, location, quantity, cost, supplier, and assumptions.
4. Planner may adjust with a required reason.
5. Authorized buyer approves purchase request under purchasing policy.
6. Acquisition workflow owns supplier commitment and purchase evidence.
7. Receiving posts physical goods through Inventory Core.
8. Actual demand and receipts feed later forecast evaluation.

No automatic purchase order, supplier email, deposit, payment, or inventory receipt is permitted from a forecast alone.

## 11. Dashboards and reports

### Executive planning view
- forecast demand and actual demand;
- stockout risk and excess exposure;
- proposed acquisition budget;
- forecast confidence and data completeness;
- store and channel comparisons.

### Buyer / planner view
- reorder queue by urgency;
- SKU and location detail;
- supplier lead-time assumptions;
- MOQ and pack constraints;
- cost estimate and approval state;
- override history and recommendation rationale.

### Category view
- fast/slow/intermittent demand;
- new-item watch list;
- condition-grade demand mix;
- aging stock and return context;
- promotion and price-change context.

All views must identify whether values are actual, estimated, or projected and display the as-of time.

## 12. Alerts and governance

Potential alerts:
- projected stockout inside supplier lead time;
- stale supplier lead-time input;
- unusually large forecast change;
- repeated forecast bias;
- missing sales or receipt data;
- recommendation exceeds approved budget threshold;
- excess-stock exposure crosses policy threshold.

Alerts create review tasks only. They do not place orders or alter inventory.

Forecast method changes, global thresholds, and planning overrides require role-scoped permission and audit evidence.

## 13. Test and acceptance criteria

- [ ] Historical actuals are separated from estimates and projections.
- [ ] Multi-channel sales are not double-counted.
- [ ] Reservations, holds, quarantine, and inbound quantities are treated consistently.
- [ ] Sparse/new-product data produces a visible low-confidence warning.
- [ ] Forecasts include method, horizon, inputs, and as-of timestamp.
- [ ] Forecast error and bias are evaluated against later actuals.
- [ ] Scenario changes cannot mutate live inventory, pricing, or orders.
- [ ] Cost and margin fields are role-restricted.
- [ ] Manual overrides record actor, reason, and version.
- [ ] Purchase requests require approved buyer authorization.
- [ ] No forecast can automatically create a purchase commitment or payment.
- [ ] Non-production tests cover missing data, stale inputs, duplicate channels, and extreme values.

## 14. Completion boundary and next gate

This is a planning specification only. No forecast has been calculated from MME actual sales data; no historical data source has been connected; no purchase order, supplier action, database change, test, or deployment has occurred.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve the demand definitions, forecast horizons, safety-stock policy, supplier input ownership, and purchasing approval limits before implementation.
