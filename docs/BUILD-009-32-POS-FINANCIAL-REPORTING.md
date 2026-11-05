# Build 009.32 — POS Financial Reporting & Profitability Intelligence Center

Status: implementation committed to a review branch. Migration replay, SQL integration tests, application authorization, source adapters, accounting validation and dashboard integration remain pending.

## Dependencies
- Build 009.20–009.26: POS hardware dispatch, device state, fleet, firmware, network security and business continuity.
- Build 009.27–009.29: security intelligence, fraud/anomaly detection and payment dispute workflows.
- Build 009.30: processor settlement batches, balance lines, reconciliation runs, bank deposit matches, cash close and settlement approvals.
- Build 009.31: settlement exception resolution and financial close snapshots.

## Purpose
Provide auditable, store-scoped financial reporting for sales, discounts, refunds, subscription revenue, tax, cost of goods sold, processor fees, chargebacks, cash differences and inventory adjustments. Produce daily reporting by store, product category, register and employee. Keep processor settlement and bank deposit reconciliation distinct from recognized sales revenue.

## Database foundation
Migration: `supabase/migrations/20261105001130_build009_pos_financial_reporting.sql`

- `mme_pos_financial_reporting_facts`: append-only financial source facts with source system, source line, fact type, business date, occurrence timestamp, IANA timezone, ISO currency, integer minor-unit amount, optional product/register/employee references and source digest.
- `mme_pos_financial_report_runs`: reproducible report metadata with store, period, currency, timezone, actor and source cutoff.
- `mme_pos_financial_report_rows`: daily grouped aggregates for store, product category, register and employee.
- `mme_pos_financial_report_summaries`: separate settlement, bank-deposit, cash-control and open-exception summary.
- `mme_pos_financial_forecast_runs` and `mme_pos_financial_forecast_rows`: explicitly illustrative short-horizon projections.

All tables enable RLS. Direct public, anonymous and authenticated table access is revoked; the trusted backend uses the service role after validating the initiating actor and store permission. Facts and report snapshots reject update/delete operations. Corrections must be supplied as new, attributable source facts; a new report run captures the corrected state.

## Financial fact ingestion
Supported fact types:
- gross sale
- discount
- refund
- subscription revenue
- sales tax
- cost of goods sold
- processor fee
- chargeback
- cash over/short
- inventory adjustment

Amounts use integer minor currency units and ISO 4217 currency codes. Positive sales/revenue/tax and negative discounts/refunds/costs/fees/chargebacks follow explicit signed-amount constraints. Cash and inventory adjustments retain their source sign.

The ingestion routine:
1. Requires active identity, active employment, no global employee-access freeze, and the explicit `pos.finance.report.import` permission scoped to the store.
2. Validates source system, source line reference, amount, currency and timezone/business-date consistency.
3. Uses a unique store/source/source-line/fact-type key to make retries idempotent.
4. Rejects a repeated source key when the amount, date, currency, occurrence timestamp or source digest conflicts; the caller must quarantine and investigate the source rather than silently overwrite it.
5. Rejects new facts that fall into a closed financial period. A correction to a closed period requires the authorized close-reopen and accounting adjustment process.

No raw payment-card PAN, CVV/CVC, PIN, track data, bank credentials or raw bank account numbers are stored.

## Report build
The backend report builder requires `pos.finance.report.build`, a store, inclusive local business-date range, currency and IANA timezone. It creates a new immutable run with a source cutoff and daily report rows.

Metrics:
- Gross sales
- Discounts
- Refunds
- Subscription revenue
- Net sales
- Sales tax (shown separately, not treated as revenue)
- Cost of goods sold
- Gross profit and gross margin
- Processor fees
- Chargebacks
- Contribution profit after recorded processor fees, chargebacks and cash over/short
- Cash over/short and inventory adjustments

The report provides daily store totals and category/register/employee comparisons. Employee and register breakdowns are restricted to authorized roles and store scope. A source fact count and report cutoff are retained for traceability.

### Accounting interpretation
- Net sales = gross sales + signed discounts + signed refunds + subscription revenue.
- Gross profit = net sales + signed cost of goods sold.
- Contribution profit = gross profit + signed processor fees + signed chargebacks + signed cash over/short.
- Sales tax remains a separately reported liability/collection metric.
- Inventory adjustments are reported separately until Finance defines approved accounting treatment.
- These are management-reporting definitions, not a substitute for the company's approved accounting policy or general ledger.

## Settlement and cash controls
A separate summary joins the Build 009.30 settlement and cash-close records:
- Processor net settlement and processor fees
- Matched bank deposit amount
- Expected and counted cash
- Cash variance
- Open settlement exceptions
- Unreconciled settlement batches

These values are not added to net sales. Settlement is a movement/collection of previously recorded transactions, not a second sale. The reporting summary is a snapshot; it does not reconcile, approve, or close a settlement batch.

## Forecasting
A basic, deterministic weekday baseline is included as a starting point:
- Uses up to the prior 28 calendar days of recorded net-sales facts.
- Calculates average daily net sales for each weekday.
- Projects the next seven calendar days only when at least four historical observations exist for that weekday.
- Stores the model identifier, as-of date, source fact count and build actor.
- Every forecast row is labelled `illustrative_projection`; missing history produces no invented estimate.

This is not a machine-learning model, budget, actual result or guaranteed forecast. It excludes seasonality, promotions, inventory availability, macroeconomic variables and planned store closures. Finance must approve any later forecasting model before operational use.

## Authorization
- `pos.finance.report.view`: report and dashboard read permission.
- `pos.finance.report.build`: create report/forecast snapshots.
- `pos.finance.report.import`: ingest trusted financial facts.

The migration adds these keys to the existing shared POS authorization gate. Grants must be explicitly assigned with appropriate store scope and expiration. CEO oversight follows the existing shared gate. Service-role execution is restricted to trusted server-side workers that validate the original actor and permission; a service-role key must never be exposed to the browser.

## Dashboard design (not live)
- CEO enterprise cockpit: consolidated revenue, net sales, gross profit, contribution profit, margin, store comparisons, trend and forecast.
- Finance: daily close state, settlement-to-bank bridge, fees, refunds, chargebacks, cash variances and source completeness.
- Store manager: only assigned store results, daily sales, category mix, register close and exceptions.
- Sales leadership: employee and register sales comparisons under least-privilege access.
- Inventory/merchandising: category profitability, COGS coverage and inventory adjustment visibility.

Every dashboard should show store, currency, reporting period, timezone, source cutoff, provisional/closed status and last successful build. Empty or incomplete source coverage must be shown as missing—not zero.

## Validation required
Run:
- `npm run test:build009:financial-reporting`
- `npm run test:build009:financial-close`
- `npm run test:build009:settlement-integrity`
- `npm run test:build009:disputes`
- `npm run test:build009:fraud-intelligence`
- All preceding Build 009 payments, refunds, cash drawer, POS state, security and hardware suites.
- `npm run lint`
- Full ordered Supabase migration replay and PostgreSQL integration tests.

Integration tests must cover source idempotency, conflicting duplicate source, signed amount constraints, invalid timezone, DST boundaries, closed-period import rejection, report source cutoff, multi-currency isolation, store isolation, grouped totals, sales-tax separation, gross/contribution profit formulas, settlement-versus-sales separation, cash summary, employee access scope, immutable facts/snapshots, forecast weekday observations, insufficient history, and report/forecast authorization.

## Not claimed complete
No migration has been applied to production Supabase. No live POS, Stripe, Verifone, inventory or subscription source adapter has been connected. No reporting dashboard has been deployed. No general-ledger posting or accounting close has been performed. Forecasts are illustrative only. Contract tests have been added but have not been executed in this workflow.
