# Build 010.47 — Cash Flow Forecasting & Financial Intelligence

## Delivered
- Base, optimistic, conservative and custom forecast scenarios.
- 1–365 day scenario horizons.
- Categorized dated inflow/outflow assumptions with confidence and provenance fields.
- Daily forecast run engine with opening cash, inflows, outflows, ending cash and lowest projected cash.
- Negative projected cash review-required flag.
- Actuals ledger with source-reference idempotency foundation.
- Forecast run history and audit ledger.
- Finance-role authenticated API, CFO dashboard, RLS and acceptance contracts.

## Release boundaries
- Forecast engine uses scenario assumptions only; actuals are not automatically imported.
- No live GL, treasury, POS, Stripe, payroll, AP or AR source adapter; no bank balances or processor settlements are independently verified.
- No subscription churn/cohort model, revenue recognition, tax engine, inventory reorder algorithm, vendor terms scheduler, debt covenant model, scenario comparison engine or automated alerts.
- Opening cash is entered by finance user and must be independently reconciled to bank/GL.
- Forecast does not yet carry forward recurring assumptions automatically; each event is dated and manually entered.
- No currency conversion or multi-currency consolidation; scenario currency defaults to USD.
- Actuals ledger is reserved for future verified imports; no user-facing import action is enabled.
- Role authorization relies on current auth app_metadata role claims; confirm production role mapping and separation of duties.
- Projections are planning estimates and must not be presented as actuals or guaranteed liquidity.

## Validation
Run `npm run test:build010:cashflow`, `npm run lint`, and `npm run build`. Apply migration after Builds 010.43–010.46 in staging. Test scenario horizon boundaries, dates, daily roll-forward, negative cash, duplicate actual source references, role gating, RLS and comparison to manually reconciled bank/GL balances. Not merged, migrated or production deployed.
