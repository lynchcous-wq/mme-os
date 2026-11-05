# Build 009.33 — POS Financial Reporting Dashboard & CEO Executive Command Center

Status: application code and contract tests committed to a review branch. Runtime validation and integration remain pending.

## Purpose
Expose the Build 009.32 financial report snapshots through a protected, responsive MME OS reporting workspace. Provide daily sales performance, profitability, category/register comparisons, processor settlement and cash-close controls, and CSV export.

## Delivered application files
- `app/internal/financial-reports/page.tsx`: responsive dashboard and report filters.
- `app/api/pos/financial-reports/route.ts`: authenticated report read and build endpoints.
- `app/globals.css`: dashboard styling and responsive layouts.
- `tests/build009-pos-financial-dashboard.test.mjs`: API/UI contract tests.
- `package.json`: `npm run test:build009:financial-dashboard`.

## Dashboard
Route: `/internal/financial-reports`

Includes:
- Reporting store UUID, period, currency and business timezone filters.
- Load latest matching immutable report snapshot.
- Build a new report snapshot when the actor has the Build 009.32 report-build permission.
- KPI cards for net sales, gross profit, gross margin, contribution profit and COGS.
- Sales breakdown for gross sales, discounts, refunds, net sales and tax.
- Processor settlement, processor fees, matched bank deposits, cash variance, open settlement exceptions and unreconciled batch counts.
- Daily net-sales bar chart and daily financial table.
- Product-category and register profitability comparisons.
- CSV export of daily store-level financial results.
- Report status, source fact count, source cutoff and build timestamp.

The interface is responsive for desktop, tablet and mobile. Empty data is explicitly shown as no report; the dashboard does not manufacture sample actuals.

## API and access controls
- GET `/api/pos/financial-reports`: loads the latest matching snapshot.
- POST `/api/pos/financial-reports`: invokes the report builder.
- Both routes use the shared employee-session authentication helper and resolve the active MME person identity.
- GET requires `pos.finance.report.view` for the requested store.
- POST requires `pos.finance.report.build` for the requested store.
- The trusted backend calls the existing authorization RPC and accesses Supabase with the server-only service-role key.
- The service key is never sent to the browser.
- Responses use private no-store caching.
- Inputs validate store UUID, actual calendar dates, date ordering, ISO currency and IANA timezone.
- The access token is held only in React component memory and is not written to local/session storage or cookies.

### Current sign-in integration limitation
The repository currently has no complete employee sign-in UI/session provider. Until that is integrated, the internal page asks an authorized employee to paste an existing Supabase employee access token and enter the store UUID. This is a temporary bridge, not the final elite employee experience. Do not expose this page as a public navigation destination or share tokens. Next integration should read the token from the approved employee auth session provider and remove manual token entry.

### Employee-level reporting safeguard
The API intentionally withholds employee-grouped report rows. Build 009.32 currently provides a general financial report view permission, not a distinct employee-finance permission. Employee-level comparisons remain disabled until a dedicated permission is added to the shared authorization gate and granted by role/store scope. Register/category views remain available to actors with the general financial report permission.

## Data and accounting presentation
- The dashboard consumes only Build 009.32 immutable report snapshots.
- Sales tax is presented separately from revenue.
- Settlement and bank deposits are presented as collections/reconciliation, not new sales.
- Gross profit and contribution profit use the signed source facts in the report snapshot.
- Missing source data is not converted into actual sales.
- CSV contains daily store-level reporting rows; it excludes employee details.

## Required environment and dependencies
- Build 009.32 migration must be applied in the target Supabase environment.
- Financial source adapters/imports must have supplied verified financial facts.
- Employee authentication environment variables and identity mapping must be configured.
- The actor must have explicit report view/build grants scoped to the store.
- Store UUID must be obtained from the authorized MME store registry; do not guess it.

## Validation
Run:
- `npm run test:build009:financial-dashboard`
- `npm run test:build009:financial-reporting`
- `npm run lint`
- `npm run build`
- Ordered Supabase migration replay and authenticated PostgreSQL integration tests.
- Manual QA for no-session, expired-session, wrong-store, view-only, build-authorized, empty-data, large-period, timezone, mobile and CSV scenarios.

No live Supabase access, production dashboard deployment, working employee sign-in integration, verified source ingestion, or completed runtime test is claimed by this change.
