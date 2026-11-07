# Build 010.86 — Inventory Forecasting, Replenishment & Automated Purchasing Recommendations

**Status:** Additive implementation contract committed on an isolated feature branch. No live forecasting model, replenishment engine, purchase recommendation service, purchase order, supplier commitment, database migration, or production deployment is claimed.

## 1. Audit findings

Repository searches on the Build 010.85 line did not locate verified inventory forecasting, demand planning, reorder-point, safety-stock, replenishment, or purchasing recommendation runtime components. Build 008 describes inventory metrics such as turnover, inventory days, aging, sell-through, slow/fast movers, and stockout frequency, but explicitly states that it is a specification rather than proof of inventory or analytics implementation. Builds 010.80 and 010.81 also document that procurement, vendor, receiving, and supplier-performance runtime authorities require verification.

Do not invent sales history, stock, lead times, supplier records, purchase orders, cost values, or forecasts. Inspect canonical product, order/POS, inventory ledger, reservation, receiving, transfer, returns, approved pricing, acquisition/COGS, vendor, finance/AP, promotion/calendar, and analytics data sources before implementation. Missing history or source authority must be visible as a data-quality blocker.

## 2. Objective and operating boundary

Provide explainable demand forecasts and replenishment recommendations to authorized buyers and executives. Recommendations are advisory until an authorized employee approves a purchase through the canonical procurement workflow. Forecasting must never independently issue a purchase order, contact a supplier, commit funds, change approved prices, reserve inventory, or adjust stock.

## 3. Data inputs and provenance

Each forecast run records source IDs/revisions, extraction time, data window, location scope, product scope, currency, timezone, model/version, parameter set, run ID, and quality checks. Candidate inputs include:
- Verified fulfilled sales units and dates from POS/order authority.
- Cancellations, voids, returns, exchanges, and refunds, separately classified.
- Canonical on-hand, reserved, available-to-promise, incoming, in-transit, quarantine, damaged, and committed quantities.
- Receiving history and supplier lead-time observations, including variability and partial deliveries.
- Transfer orders and confirmed destination receipts.
- Approved promotions, markdowns, seasonality, holidays, and planned events.
- Stockout periods and unavailable exposure, so censored demand is not mistaken for zero demand.
- Approved acquisition cost, purchase minimums, pack sizes, and supplier terms where finance/procurement authorize access.

Do not use quotes, abandoned carts, web views, or unverified orders as fulfilled demand. Such signals may be displayed separately as weak indicators with explicit labels and approved methodology. Exclude test, fraud, duplicate, and reversed transactions under documented rules.

## 4. Forecast design

Support forecast horizons appropriate to replenishment and planning, configurable by product class and location. Candidate methods include simple moving average, weighted moving average, seasonal baseline, intermittent-demand methods, and validated statistical/ML models. Select the method by measured out-of-sample performance, not novelty.

Each recommendation includes:
- Forecast demand by day/week and horizon.
- Baseline, model, confidence interval or uncertainty band where supported.
- Actual-versus-forecast history and forecast error.
- Trend/seasonality/promotion assumptions.
- Data coverage, last refreshed time, and quality warnings.
- Model/version and explanation of key drivers.
- Manual override and reason history, if authorized.

Cold-start products, sparse sales, new launches, clearance items, and highly intermittent accessories require conservative fallback rules and explicit low-confidence labels. Do not fabricate a confident forecast where history is insufficient.

## 5. Available supply and demand position

Calculate projected inventory position only from canonical records and a documented as-of time. Distinguish:
- Physical on-hand.
- Reserved/held and committed demand.
- Available-to-promise.
- Confirmed purchase/receiving quantities by expected date.
- In-transit transfer quantities and destination.
- Quarantine, inspection, damaged, and non-sellable quantities.
- Confirmed sales/fulfillment demand.
- Expiring or stale reservations under the authoritative reservation service.

Do not double-count a transfer as both source and destination stock. Do not count unapproved requisitions, draft POs, supplier promises, or unconfirmed inbound quantities as confirmed supply. Use time-phased projected inventory, not a single static on-hand number.

## 6. Reorder policy and recommendation calculation

Provide configurable policy inputs by product/location:
- Target service level and replenishment horizon.
- Supplier lead-time distribution and review cadence.
- Safety-stock method and minimum/maximum bounds.
- Reorder point and order-up-to target.
- Minimum order quantity, pack size, case multiple, and supplier constraints.
- Budget/cash guardrails and approved category restrictions.
- Product lifecycle status, end-of-life, substitution, and clearance rules.

Illustrative policy only (not a universal default):
- Reorder point = expected demand during replenishment lead time + approved safety stock.
- Suggested order quantity = max(0, target stock position − projected inventory position), rounded to approved pack/MOQ constraints.

Every formula, input, override, and policy version is recorded. Recommendations must identify why a product is suggested, why quantity was rounded, and what would change the recommendation. Never treat an illustrative formula as approved accounting/procurement policy.

## 7. Recommendation lifecycle and approvals

Logical states:
1. Generated.
2. Data-quality review.
3. Ready for buyer review.
4. Accepted, edited, deferred, or rejected.
5. Pending budget/finance approval where required.
6. Approved requisition.
7. Converted through canonical procurement workflow.
8. Ordered / partially received / received / closed or cancelled.

The recommendation stores the forecast run, source snapshot, product/location, quantity proposal, supplier option references, expected arrival window, estimated cost basis and confidence, policy, rationale, reviewer, approval, and decision history.

An edited quantity or supplier selection creates a new proposal version. Approval binds to the exact proposal and cost/budget assumptions. Forecast automation may generate and prioritize recommendations but cannot approve them. A purchase order is created only by the canonical procurement authority after required approvals.

## 8. Supplier and purchasing constraints

- Use the canonical approved vendor master and supplier-product mappings.
- Show observed lead-time and delivery reliability only when supported by verified PO/receipt history.
- Respect vendor suspension, compliance restrictions, MOQ, pack size, payment terms, and purchase restrictions from authoritative systems.
- Do not store vendor banking instructions or sensitive payment data in forecasting screens.
- Compare supplier options using approved price and terms evidence; estimated quote data is not a binding offer.
- Respect approved budget and delegated purchasing limits.
- Preserve source references and approval for supplier substitutions or split orders.

## 9. Dashboards, alerts and automation

Provide authorized views for:
- Demand forecast and confidence by product/location.
- Days of supply and projected stockout date.
- Below-reorder-point items and recommended order quantities.
- Excess/slow-moving/aging stock and potential overstock.
- Supplier lead-time variance and inbound risk.
- Forecast bias/error and data-quality coverage.
- Recommendation queue, approval aging, and purchase commitments.
- Budget exposure using clearly labeled estimated/approved cost bases.

Automate scheduled refresh, stale-data alerts, forecast quality checks, low-stock alerts, recommendation generation, approval routing, and safe idempotent retries. Alerts are advisory and do not create orders or change stock. Avoid alert storms through deduplication, thresholds, and quiet periods.

## 10. Security, audit and privacy

- Server-side identity, role, location, category, and legal-entity authorization.
- Separate read-only forecast access from buyer edit, approver, finance, and procurement permissions.
- Restrict cost, margin, supplier, and budget data to authorized roles.
- RLS and audit all forecast access, exports, overrides, decisions, approval, and procurement handoff.
- Protect customer and employee data; aggregate demand signals wherever possible.
- Keep model prompts and external AI payloads free of unnecessary personal or restricted financial data.
- Record model inputs/outputs and deterministic calculation versions for reproducibility.

## 11. Acceptance and regression tests

- Forecast uses only verified, eligible sales and supply records with source revisions.
- Voids, cancellations, returns, duplicates, and test transactions follow explicit demand rules.
- Stockout periods are flagged and not blindly treated as zero demand.
- Inbound, transfers, reservations, and committed quantities are not double-counted.
- Unknown lead time, missing history, stale inventory, and cold-start items produce visible low-confidence/blocker states.
- Forecast and recommendation reproduce from stored input snapshot and model/policy version.
- Reorder point, safety stock, lead time, MOQ, pack-size rounding, and target-stock calculations pass deterministic fixtures.
- Recommendations never directly create POs, supplier commitments, payment instructions, reservations, or stock adjustments.
- Unauthorized employees cannot access restricted cost, supplier, budget, or location data.
- Approval is invalidated by material proposal or cost changes.
- Duplicate scheduled runs do not create duplicate recommendation records or downstream requisitions.
- Forecast errors, bias, and confidence reporting are validated against holdout periods.
- Regression tests preserve customer sign-in, employee sign-in, product catalog, POS, warehouse, receiving, transfers, counts, returns, valuation/COGS, and website availability behavior.

## 12. Runtime implementation gates

Do not mark Build 010.86 implemented or live until:
1. Canonical source schemas and provider ownership are inspected in target environments.
2. Data quality, sales-demand classification, stockout treatment, lead-time, and forecast horizon policies are approved by operations/procurement/finance.
3. Reorder, safety-stock, service-level, MOQ, pack-size, budget, and approval rules are explicitly configured.
4. Forecast model selection is validated with historical holdouts and documented accuracy thresholds by product class.
5. Additive migrations, RLS, audit, and data-retention controls are reviewed.
6. Forecast pipeline, recommendation service, buyer review UX, and approved procurement handoff are implemented.
7. Unit, integration, model-quality, concurrency, authorization, privacy, and idempotency tests pass.
8. Staging forecasts reconcile to canonical sales, inventory, receiving, and transfer snapshots.
9. Regression tests preserve sign-in, catalog, POS, warehouse, receiving, transfers, cycle counts, returns, COGS, and website stock behavior.
10. Procurement, finance, operations, and security owners approve rollout; production deployment and post-deploy evidence record exact commit and environment.

**Release note:** This contract is not a demand forecast, approved purchase recommendation, purchase requisition, supplier communication, purchase order, financial commitment, stock reservation, production migration, or deployment approval. No runtime forecasting or purchasing feature is claimed by this document.
