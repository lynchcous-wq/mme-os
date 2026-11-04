# Build 005.24 — Inventory Intelligence, AI Recommendations, and Executive Command Dashboard

**Status:** Intelligence and dashboard design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines inventory decision support, AI-assisted recommendations, exception prioritization, and executive/store management views. Inventory Core remains the authority for stock facts and movements; AI recommendations never directly change inventory, pricing, purchasing, payments, or employee permissions.

## 1. Purpose

Give authorized MME leaders a reliable view of inventory health and actionable recommendations across receiving, availability, aging, transfers, purchasing, auctions, returns, refurbishment, and liquidation.

The dashboard must distinguish verified facts from estimates, forecasts, recommendations, pending approvals, and completed transactions.

## 2. Authority and source boundaries

- **Build 005 Inventory Core:** stock identity, unit/lot quantity, location, condition, movements, holds, reservations, and availability.
- **Build 005.15:** demand forecasts and replenishment recommendations.
- **Build 005.16:** inventory cost lineage, valuation, and profitability definitions.
- **Build 005.17:** transfer and warehouse state.
- **Build 005.19:** counts, discrepancies, and shrinkage evidence.
- **Build 005.20:** supplier and purchase-order workflow.
- **Build 005.21:** pricing, markdown, and margin approval.
- **Build 005.22:** auction, bulk-lot, and liquidation outcomes.
- **Build 005.23:** returns, warranty, repair, and refurbishment lifecycle.
- **Build 026:** enterprise analytics and reporting.
- **Build 004:** identity, roles, permissions, and audit actor.

The dashboard is a read-oriented decision surface. Commands must be routed to the authoritative owning service and independently authorized there.

## 3. Executive command dashboard

Proposed CEO view:
- total sellable units and quantity by location;
- inventory value using the approved valuation basis and as-of timestamp;
- retail/reference value shown separately from carrying value;
- stock aging and slow-moving exposure;
- top categories and models by sell-through;
- stockout and excess-stock alerts;
- inbound acquisition lots and receiving exceptions;
- inventory reserved for orders and active auctions;
- transfers in transit and overdue receipts;
- returns, quarantine, repair, and refurbishment backlog;
- shrinkage and reconciliation exceptions;
- purchase recommendations awaiting approval;
- markdown/liquidation recommendations awaiting approval;
- data freshness, failed syncs, and unresolved critical exceptions.

Every metric must provide a definition, scope, date range, source, and drill-down path. CEO visibility does not bypass restricted customer, employee, serial/IMEI, or financial-detail permissions.

## 4. Store manager and operational views

Role-specific workspaces may include:
- receiving queue and manifest discrepancies;
- put-away and location capacity;
- pick/pack and local pickup readiness;
- low-stock and replenishment tasks;
- transfer dispatch and receipt;
- cycle-count assignments and variance review;
- returns awaiting inspection;
- repair and refurbishment work queue;
- auction listing eligibility and settlement exceptions;
- price/markdown approvals;
- daily close and unresolved inventory events.

Views should prioritize tasks that the logged-in role is authorized to resolve. Do not display controls that imply an approval privilege the user does not possess.

## 5. AI-assisted recommendation engine

AI may generate recommendations such as:
- investigate a stockout or unusual demand spike;
- transfer eligible stock between locations;
- review a purchase quantity or supplier lead time;
- inspect a slow-moving category for markdown eligibility;
- bundle or liquidate excess stock;
- investigate repeat defects or supplier discrepancies;
- prioritize a cycle count based on risk signals;
- review an auction reserve or lot composition;
- identify data conflicts between inventory and sales channels.

Each recommendation must include:
1. recommendation ID and version;
2. recommendation type and priority;
3. affected SKU/unit/lot/location references;
4. source facts and as-of timestamps;
5. explanation of the signal and assumptions;
6. confidence or evidence-strength label with defined meaning;
7. expected benefit and uncertainty range where supportable;
8. risks, constraints, and policy checks;
9. proposed next action and owning authority;
10. expiration/review date and status.

AI must not invent source facts, infer unverified stock, or present a forecast as an actual result.

## 6. Recommendation lifecycle and approvals

Proposed lifecycle:
1. Generated
2. Evidence review
3. Ready for authorized review
4. Approved / rejected / deferred
5. Executed by owning workflow
6. Outcome measured
7. Closed or superseded

Approval is separate from execution. A recommendation to purchase must route through Build 005.20; a price change through Build 005.21; a transfer through Build 005.17; a liquidation through Build 005.22. The AI layer cannot bypass those approval controls.

Record reviewer, decision, rationale, policy version, execution reference, and measured outcome.

## 7. Forecasts, scenarios, and financial presentation

Dashboard metrics must clearly label:
- actual completed transactions;
- current inventory facts;
- pending orders or settlements;
- estimated landed costs;
- approved inventory valuation;
- forecast demand;
- projected sell-through;
- AI-generated recommendations;
- hypothetical scenario outputs.

Scenario analysis may compare demand, lead time, markdown, transfer, and acquisition assumptions. It must not alter operational stock or financial records.

Gross profit and gross margin must be calculated using approved definitions and reconciled transaction data. Retail price less estimated cost must not be shown as realized profit.

## 8. Data quality and freshness

Every dashboard tile should identify:
- source system;
- last successful refresh;
- event or snapshot time;
- freshness target;
- stale/unavailable state;
- reconciliation status where relevant.

If source data is delayed, contradictory, or unavailable:
- show the stale/unavailable warning;
- preserve the last known value with its timestamp;
- do not silently substitute an estimate;
- suppress recommendations that require trustworthy current data;
- create an exception for the owning team.

## 9. Alerts, prioritization, and escalation

Prioritize alerts using configurable severity, business impact, age, and responsible team. Examples:
- stock committed beyond available quantity;
- duplicate active listings;
- unresolved serialized-unit conflict;
- receiving variance;
- overdue transfer receipt;
- inventory movement/event delivery failure;
- stock marked sellable without required inspection;
- purchase approval exceeding its review window;
- margin-floor exception awaiting decision;
- auction winner/payment handoff mismatch;
- warranty/repair backlog;
- count variance requiring investigation.

Escalation rules must be versioned and approved. Alerts should be deduplicated and idempotent, with clear owner and resolution evidence.

## 10. Natural-language inventory assistant

An authorized user may ask questions such as:
- “Which TVs are below the approved reorder point?”
- “What inventory is waiting for inspection?”
- “Which lots have the highest unresolved receiving variance?”
- “Show stock aging by location.”
- “Which recommendations are awaiting my approval?”

The assistant must:
- resolve the user's identity and permissions server-side;
- constrain retrieval to authorized locations and fields;
- cite internal records or report references in the answer;
- state data freshness and relevant filters;
- ask for clarification where the requested metric is ambiguous;
- refuse or mask unauthorized personal, device-identifier, or financial detail.

Natural-language commands that would change data must be converted into a preview and approval workflow, never executed solely from generated text.

## 11. Security, privacy, and audit

- Enforce Build 004 role and location scope at the server/service layer.
- Apply least privilege to cost, margin, supplier, customer, and device-identifier details.
- Keep AI prompts and outputs from becoming an authorization source.
- Prevent cross-location data leakage.
- Log recommendation generation, source references, access decisions, approvals, and execution outcomes.
- Do not expose full serial/IMEI or customer personal data in general dashboard tiles, alerts, or model context.
- Apply retention and export controls from Build 005.14.
- Treat application-side identity/session enforcement as unverified until separately validated.

## 12. Performance and usability

- Support configurable date ranges, location, category, SKU, condition, and channel filters.
- Provide drill-down from summary to source records.
- Offer table, chart, and comparison views where appropriate.
- Keep operational queues usable on store tablets and mobile screens.
- Paginate large datasets and avoid loading all serialized records into a dashboard.
- Cache only with explicit freshness metadata and authorization-safe scoping.
- Provide accessible labels, keyboard navigation, and clear empty/error states.

## 13. Measurement and model governance

Track:
- recommendation acceptance, rejection, and deferral rates;
- recommendation execution success;
- forecast error by horizon/category;
- stockout and excess-stock outcomes;
- markdown and liquidation recovery;
- transfer benefit and cost;
- alert precision and resolution time;
- data freshness and reconciliation health;
- user-reported incorrect or unsafe recommendations.

Version models, prompts, features, thresholds, and policies. Review drift and harmful recommendation patterns. Provide a way to disable AI recommendations while preserving standard reports and workflows.

## 14. Acceptance criteria

- [ ] Executive metrics have definitions, scope, source, and timestamps.
- [ ] Actual, estimated, forecast, and recommended values are visually distinct.
- [ ] Dashboard reads authoritative inventory facts rather than maintaining stock balances.
- [ ] Role and location filters are enforced server-side.
- [ ] AI recommendations include evidence, assumptions, uncertainty, and owning authority.
- [ ] Recommendations cannot directly purchase, transfer, adjust, markdown, liquidate, or sell stock.
- [ ] Approved actions execute through their owning workflows.
- [ ] Stale/conflicting data is identified and suppresses unsafe recommendations.
- [ ] Natural-language answers respect permissions and cite source records.
- [ ] Restricted customer and device identifiers remain masked.
- [ ] Recommendation and execution outcomes are auditable.
- [ ] AI can be disabled without disabling core inventory operations.
- [ ] Tests cover role leakage, stale data, unsupported claims, duplicate alerts, and unauthorized action attempts.

## 15. Completion boundary and next gate

This is a design specification only. No AI model, dashboard, data pipeline, report, alert, or integration was configured. No code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve dashboard role layouts, metric definitions, freshness targets, recommendation confidence methodology, escalation thresholds, and model governance before implementation.
