# Build 009.56 — Enterprise Inventory Intelligence & Automated Market Research

## Purpose
Create verified product identities, structured market observations, demand forecasts, stock alerts and approval-gated procurement recommendations.

## Product identity
Fingerprints normalize manufacturer, model, storage, memory, screen and connectivity. Market observations are rejected unless the fingerprint has been verified at confidence 90 or higher. Exact model/specification and condition matching are required before comparables should influence pricing. Automated matching is advisory until a trusted reviewer verifies identity.

## Market research
Store source, listing reference, observed price, currency, condition, shipping, availability, confidence, observation time and expiry. Source adapters are not included; only trusted backend ingestion may write observations. Do not scrape prohibited sites or treat sponsored, stale, duplicate or mismatched listings as comparable.

## Demand intelligence
Demand snapshots capture date-window sales, returns, on-hand, reserved and inbound stock plus unit cost. The initial forecast uses simple net unit velocity. It reports days of cover, forecast units and a reorder quantity. Forecast confidence is a conservative heuristic, not a statistically calibrated probability.

## Procurement
The system creates recommendations only. It does not place orders or commit funds. A different authorized approver must approve the request. Vendor selection, lead time, MOQ, cash constraints, purchase budgets, supplier reliability and existing open POs require future integrations before recommendations can be considered purchase-ready.

## Alerts
Reorder suggestions create deduplicated alerts. Slow-moving, excess stock and market-price-shift alert types are reserved for future calibrated rules and should not be emitted until their thresholds are configured.

## Security
All tables use RLS and deny browser-role direct access. Service-role RPCs must only be called by trusted APIs. The application authorization layer must verify user identity, location scope, source permissions and procurement authority. Audit history is append-only.

## Dependencies
Build 009.55 recovered pricing; authoritative inventory snapshots, POS sales, returns, product catalog, vendor procurement and market-research source adapters.

## Validation
Run `npm run lint`, `npm run test:build009:inventory-intelligence`, and prior Build 009.53–009.55 suites. PostgreSQL integration tests must cover verified identity, stale observations, model mismatch, demand netting, zero velocity, reserved stock, idempotent alerts, independent procurement approval and location scoping.

## Rollout boundary
Draft implementation only. No live market scraping, vendor ordering, supplier integrations, predictive ML, live inventory synchronization, production deployment or user interface is claimed.
