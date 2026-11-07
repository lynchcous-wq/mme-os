# Build 010.88 — Inventory Intelligence Dashboard, Executive KPIs & Real-Time Operations Reporting

**Status:** Additive implementation contract committed on an isolated feature branch. No live inventory dashboard, governed analytics pipeline, real-time data feed, KPI calculation service, migration, or production deployment is claimed.

## 1. Audit findings

Repository searches on the Build 010.87 line did not locate verified inventory intelligence dashboards, KPI reporting, real-time inventory analytics, or executive inventory reporting runtime components. Build 008 defines a governed, read-only BI projection and inventory metrics, but explicitly states that analytics and the broader inventory platform are not established by that specification. Build 010.79 defines a reconciliation dashboard contract and likewise states that no live dashboard/query/worker is claimed. Builds 010.85–010.87 define financial, forecasting, and lifecycle metrics that require canonical sources and policy-controlled calculations.

Do not invent live balances, valuation figures, sales history, employee metrics, or freshness claims. Inspect canonical catalog, inventory ledger, location, POS/order, payment, reservation, warehouse, receiving, transfer, returns, acquisition/COGS, pricing, forecasting, lifecycle, identity, audit, and analytics sources before implementation. The dashboard is a read-only projection, never a stock or accounting mutation interface.

## 2. Objective and audiences

Provide one trustworthy, role-scoped view of inventory health and performance for:
- CEO/executives: company-wide and authorized location/category oversight, financial exposure, risk, trends, and exceptions.
- Operations/inventory leadership: stock accuracy, availability, aging, movement, transfer, receiving, and reconciliation.
- Store/warehouse managers: location-scoped stock, fulfillment, receiving, count, and task queues.
- Buyers/procurement: demand forecast, reorder recommendations, inbound risk, supplier delivery performance, and approval queue.
- Finance: approved valuation, cost, COGS, write-off and reconciliation metrics.
- Sales/customer-facing staff: only operationally necessary sellable availability and approved public product facts.

Each audience sees only authorized entities, locations, categories, financial fields, and employee data.

## 3. Dashboard information architecture

### Executive overview
- Total physical on-hand units and quantity by status.
- Available-to-promise, reserved/held, incoming, and in-transit quantities separately.
- Approved inventory carrying value at a stated valuation date and currency.
- Estimated retail value and estimated gross-profit potential, clearly marked as estimates.
- Verified sales/fulfillment, COGS and gross profit only when authoritative events reconcile.
- Aging and slow-moving inventory exposure.
- Stockout risk, replenishment recommendations, and supplier/inbound risk.
- Count accuracy, unresolved variance, shrink and adjustment trends.
- Open receiving, transfer, return, repair, and disposition exceptions.
- Data freshness, source coverage, reconciliation health, and system status.

### Operations workbench
- Location and status balance.
- Receiving, inspection, putaway, picking/packing and fulfillment queues where runtime sources exist.
- Transfers awaiting dispatch, receipt, or discrepancy resolution.
- Reservations and expiry exceptions.
- Cycle-count plans, progress, variances, approvals, and posting failures.
- Returns awaiting inspection and authorized disposition.
- Aging cases, task ownership, SLA, and escalations.
- Inventory movement and source-to-ledger reconciliation drill-down.

### Buyer and finance views
- Demand forecast and forecast accuracy.
- Days of supply, reorder threshold, projected stockout and suggested replenishment.
- Inbound quantity by confirmed status and expected date.
- Supplier lead-time and delivery performance from verified PO/receipt records.
- Cost/valuation by approved policy and date.
- Sale-line COGS, gross profit/margin, write-offs and financial reconciliation.
- Approval queues and unresolved cost/source exceptions.

## 4. KPI dictionary and formulas

Every KPI must have a governed definition with owner, source authority, formula/version, included/excluded states, scope, refresh cadence, timezone, currency, and actual/estimated classification.

Candidate definitions (final formulas require domain-owner approval):
- **Physical on-hand:** canonical ledger quantity physically held at the selected location/status as of the stated ledger watermark; exclude in-transit stock.
- **Available-to-promise (ATP):** canonical availability-service result; do not derive by subtracting guessed reservations from a stale balance.
- **Reserved/held:** active canonical reservations not yet committed, released, or expired.
- **Incoming:** confirmed accepted purchase/receiving quantities not yet posted as physically received, displayed separately from on-hand.
- **In-transit:** dispatched transfer quantity not yet accepted at destination.
- **Inventory carrying value:** approved Accounting valuation of eligible inventory at the stated valuation date; not retail value.
- **Estimated retail value:** eligible quantity multiplied by current approved selling price; explicitly estimated and excludes unsupported/stale prices.
- **Gross-profit potential:** estimated retail value less approved cost basis for eligible units; not realized profit.
- **Recognized COGS:** authoritative posted cost associated with eligible recognized sale/fulfillment events under Accounting policy.
- **Gross profit:** recognized net selling revenue less recognized COGS, under the approved revenue/return/discount treatment.
- **Inventory turnover:** approved period COGS divided by average inventory carrying value for the same period; define averaging and period conventions.
- **Days of supply:** projected eligible stock divided by forecast demand rate over the stated horizon; display low confidence or unknown when demand history is insufficient.
- **Sell-through:** eligible units sold during a defined period divided by the approved available/supply denominator for that same cohort and period; define denominator before publication.
- **Stockout rate:** time or product-location intervals unavailable for sale divided by eligible monitored intervals; do not infer stockout from missing data.
- **Count accuracy:** count lines/units within approved tolerance divided by all eligible completed count lines/units; report quantity- and value-weighted variants separately.
- **Aging:** elapsed time from the selected immutable lifecycle event to as-of time, segmented by approved cohort and status.
- **Shrink/adjustment rate:** approved net adjustment quantity/value over a documented inventory or sales denominator; show shortage and overage separately.
- **Forecast error/bias:** compare forecasts to eligible actual demand using approved holdout periods and metrics (e.g. WAPE/MAE/bias); handle intermittent/zero demand explicitly.

Do not publish a metric with an unresolved definition, missing source, or incompatible denominator.

## 5. Data freshness and real-time behavior

- Every tile, chart, table, and export shows as-of timestamp, source watermark, last successful refresh, and freshness state.
- Define source-specific freshness SLAs; a single dashboard-wide “live” label is prohibited if any required source is stale or incomplete.
- Use explicit states: current, delayed, stale, partial, unavailable, or unknown.
- Preserve last-known-good data with a visible timestamp and warning; do not present stale/unknown as zero.
- Distinguish event time from ingestion/processing time and disclose lag.
- Support incremental refresh/event-driven updates where canonical sources permit; use bounded polling or scheduled snapshots otherwise.
- Reconcile aggregate totals to canonical records and identify source coverage and missing partitions.
- Never claim real-time updates until measured end-to-end latency meets the approved SLA.

## 6. Filters, drill-down and exports

Authorized filters may include legal entity, store/location, warehouse zone, category, brand, product, condition, lifecycle status, acquisition batch, channel, date range, supplier, and exception owner.

Drill-downs resolve to canonical product/unit, movement, order, receiving, transfer, count, return, cost, forecast, or lifecycle records using stable safe references. Do not expose serial/IMEI, customer PII, supplier confidential data, cost/margin, or employee information beyond the viewer's permissions.

Exports must include metric definitions, filters, source watermarks, as-of date, timezone, currency, and actual/estimated labels. Enforce export permissions, audit exports, and apply row/column-level redaction. Do not allow dashboard exports to become an alternate source of truth.

## 7. Alerts, thresholds and executive exception view

Surface actionable exceptions:
- Source feed stale or missing.
- Ledger/source reconciliation incomplete or failed.
- Availability mismatch or reservation expiry issue.
- Low stock, projected stockout, and replenishment approval overdue.
- Overstock, aging threshold, and end-of-life risk.
- Receiving/inspection/transfer/return backlog.
- Count variance, repeated discrepancy, and adjustment posting failure.
- Missing cost provenance, valuation mismatch, or COGS/GL reconciliation failure.
- Unauthorized access or suspicious export events.

Each alert includes source, severity, affected scope, first/last seen, owner, SLA, policy version, evidence link, and deduplication key. Alerts do not mutate stock, prices, orders, payments, or accounting balances. Acknowledge/assign/resolve actions operate on the authoritative task/case service.

## 8. Security and governance

- Server-side authentication and authorization; RLS and scope enforcement at the data/query layer.
- Separate dashboard visibility from the ability to execute underlying operational or financial actions.
- Apply legal-entity, location, department, category, and sensitive-field permissions.
- Finance-only cost/valuation/COGS access; executives receive only authorized aggregated or drill-down data.
- Restrict employee activity reporting to approved operational purposes and HR permissions; avoid unnecessary surveillance.
- Mask/encrypt serial/IMEI and omit from broad analytics projections.
- Keep customer-facing APIs separate from internal analytics; no internal cost, margin, supplier, or exception data leaks to storefront.
- Audit access to sensitive dashboards, filters, drill-downs, exports, and permission changes.
- Use least-privilege service identities and avoid exposing provider credentials or raw restricted source records.

## 9. Performance, reliability and accessibility

- Use governed read models/materialized projections only after canonical source ownership is established.
- Define pagination, query limits, timeouts, caching, refresh cadence, and concurrency budgets.
- Avoid full-table scans on transactional systems; protect POS/checkout and operational write paths.
- Provide accessible keyboard navigation, readable chart alternatives, responsive layouts, clear labels, and downloadable tabular detail where authorized.
- Display empty, loading, partial, error, and stale states explicitly.
- Monitor refresh failures, latency, query cost, data drift, reconciliation failures, and export volume.

## 10. Acceptance and regression tests

- KPI calculations reproduce from a fixed source snapshot and definition version.
- Physical, ATP, reserved, incoming, and in-transit quantities are distinct and do not double-count.
- Financial metrics use approved valuation, price, revenue, return, and COGS versions.
- Estimated retail value and gross-profit potential are never labeled actual.
- Missing/stale source data renders stale/unknown/partial, never a false zero or clean result.
- Partial source coverage is visible and cannot produce a false healthy executive status.
- Drill-down totals reconcile to authorized canonical records.
- Filters and aggregates enforce location, legal-entity, role, and sensitive-column access.
- Customer/public endpoints expose no internal cost, margin, supplier, employee, serial, or exception data.
- Exports retain filters, source watermark, currency/timezone, metric definitions, and redaction.
- Dashboard reads cannot mutate inventory, price, POS, payments, returns, or accounting records.
- Load and query limits do not degrade POS, checkout, warehouse, or other critical paths.
- Regression tests preserve customer sign-in, employee sign-in, catalog, POS, warehouse, receiving, transfers, cycle counts, valuation/COGS, forecasting, lifecycle workflows, and website availability.

## 11. Runtime implementation gates

Do not mark Build 010.88 implemented or live until:
1. Canonical data sources, schema ownership, source watermarks, and access controls are inspected in target environments.
2. KPI definitions and metric owners are approved by operations, finance, procurement, and executive stakeholders.
3. Read-model architecture, freshness SLAs, event/snapshot strategy, retention, and query budgets are approved.
4. Role, location, legal-entity, sensitive-field, and export permissions are mapped and tested.
5. Additive analytics projections, APIs, dashboard UI, alert integration, and observability are implemented without duplicating transactional masters.
6. Data lineage, source reconciliation, stale/partial behavior, and audit are verified.
7. Unit, metric-fixture, integration, authorization, privacy, accessibility, load, and failure-mode tests pass.
8. Staging dashboards reconcile to canonical inventory, POS, receiving, transfer, count, return, valuation, COGS, and forecast snapshots.
9. Regression tests preserve customer/employee sign-in, product viewing, POS, warehouse, and all preceding inventory workflows.
10. Operations, finance, security, and executive owners approve rollout; production deployment and post-deploy evidence record exact commit, environment, and measured freshness.

**Release note:** This contract is not a live dashboard, KPI feed, inventory balance, financial statement, alert service, stock mutation interface, production migration, or deployment approval. No runtime analytics feature or real-time reporting capability is claimed by this document.
