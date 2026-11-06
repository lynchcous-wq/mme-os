# Build 009.71 — Warranty Intelligence & Analytics

## Scope
Adds a KPI fact ledger, versioned analytics snapshots, approved forecast assumptions and provider scorecards. Read models summarize warranty financial entries, lifecycle events and provider SLA events. The dashboard can compare categories, providers and periods without blending currencies or mixing realized results with estimates.

## KPI governance
Every imported KPI fact requires metric code, period, unit, currency where applicable, source system/reference, actor and idempotency key. Projections require a model version. Forecast assumptions are effective-dated, rationale-backed and approved. Corrections should be new source facts or governed superseding records, not silent edits to history.

## Actual versus projected
Actual and projected values remain separate fields and separate realization classes. Actual warranty margin must derive only from approved actual revenue, repair parts/labor costs, customer charges and provider recovery entries; unapproved entries must not be presented as realized financial performance. Provider claim approval is not a received reimbursement. Use matched settlement evidence for actual recovery.

## Dashboard metrics
Supports warranty cost by category, claims-to-sales ratio when sales denominator facts are supplied, repair/replacement cost comparisons when both source measures exist, provider response SLA, reimbursement match rate, late/unavailable events, lifecycle events and expiration/renewal trends. Missing denominators must display unavailable—not zero or a fabricated ratio. Use consistent period boundaries and currencies.

## Forecasting
Expiration, claim-volume and reserve forecasts must identify model version, assumptions, as-of date and confidence limits where available. Forecasts are planning estimates, not booked liabilities or actual claims. Do not infer provider rankings where sample sizes are insufficient; show volume and confidence context.

## Security
RLS on all analytics tables; browser grants revoked. Backend dashboard routes must enforce executive/finance role authorization and aggregate-only customer data. Do not expose customer identifiers, internal fraud scores or sensitive claim documents in executive charts.

## Validation
Run npm run lint and npm run test:build009:warranty-analytics plus existing warranty financial, provider, lifecycle and risk suites. PostgreSQL integration tests must verify currency isolation, actual/projection separation, approval filtering, missing denominator behavior, provider sample-size handling and role access.

## Rollout boundary
Draft analytics schema/read models only. No dashboard UI, scheduled aggregation worker, sales-data feed, actual KPI import, forecast model execution, production migration replay or deployment is claimed.
