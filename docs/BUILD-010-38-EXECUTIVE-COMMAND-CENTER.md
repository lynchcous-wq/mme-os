# Build 010.38 — Enterprise Executive Command Center

## Delivered
- Executive dashboard route at `/executive/command-center`.
- Authenticated access gate at `/api/executive/command-center`.
- Finance and workforce source-ledger aggregation through existing APIs.
- Reporting windows (7, 30, 90 and 365 days) and manual refresh.
- Open payables/receivables, chart-of-accounts and journal counts.
- Compensation profile, time-entry, commission-ledger and performance-review summaries.
- Source availability, stale/missing-source caveats and integration coverage panel.
- Acceptance contract tests.

## Data integrity and boundaries
- Dashboard values are operational summaries of source ledger records, not audited financial statements or GAAP recognition.
- Open payable/receivable totals are gross invoice amounts, not net balances or aging-adjusted cash forecasts.
- Commission exposure is the sum of pending, verified and approved commission ledger rows; it is not payroll payable.
- Finance and HR APIs retain their own role authorization; dashboard access alone does not grant access to their data.
- POS sales, subscription revenue, inventory valuation, store profitability, bank cash position and cross-system risk feeds are explicitly unavailable until their source integrations are implemented and verified.
- No money movement, payroll disbursement, bank feed connection, tax filing or automated executive distribution is performed.

## Release validation
Run `npm run test:build010:executive-command-center`, `npm run lint`, and `npm run build`. Verify all role combinations against real app_metadata claims and test source API failures. Not merged, migrated or production deployed.
