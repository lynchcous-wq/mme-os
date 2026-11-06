# Build 009.66 — Enterprise Warranty Financial Intelligence

## Scope
Adds a warranty financial fact ledger, approved reserve assumptions, reserve snapshots and finance approval workflow. It extends Build 009.64 repair/provider claim operations and does not replace the corporate general ledger or subscription billing system.

## Actuals vs projections
Every financial entry is explicitly classified as actual or projection. Actual entries require independent finance approval before they qualify as approved actuals. Forecasts remain forecasts and are never included in approved actual totals. Warranty revenue should be recorded from verified billing/contract events, not merely from an estimate or quote. Provider recoveries are not cash until settlement evidence is reconciled.

## Cost categories
Track warranty revenue, parts cost, labor cost, provider recovery, customer charge and reserve adjustment by repair case, provider claim, currency and effective date. Source references and idempotency keys prevent duplicate imports. Actual amounts must reconcile to source billing, inventory issue, approved time/labor and provider settlement evidence before finance approval.

## Reserve model
Approved assumptions store expected claim frequency, severity, administration cost and effective date. Snapshot formula: active contracts × expected frequency = expected claims; expected claims × severity + expected claims × administration cost = modeled reserve. This is a management estimate, not an actuarial opinion or posted general-ledger liability. Finance must approve assumptions and snapshots, assess contract term/runoff, inflation, exclusions, currency, claims development and jurisdiction-specific accounting treatment.

## Reporting
The summary view separates projected amounts from approved actual amounts by category and currency. Profitability reporting must be computed only after warranty revenue and all repair/provider costs are reconciled on a consistent cohort and currency basis. Never net claim submissions against actual costs as if paid.

## Security
RLS on all new tables; no direct browser access. Service-role RPCs are restricted to authenticated finance APIs with finance-role and store/entity scope checks. Events are append-only. Do not store card data or unnecessary customer/device identifiers in financial notes.

## Validation
Run npm run lint, npm run test:build009:warranty-financial, and existing warranty-repair, financial-reporting, inventory-ledger, payroll and billing reconciliation suites. Integration tests must cover duplicate import, cross-case claim mismatch, approval separation, currency separation, assumption effective dating and snapshot replay.

## Rollout boundary
Draft implementation only. No production migration replay, billing connector, inventory/payroll actual import, provider payout webhook, actuarial certification, general-ledger posting or deployment is claimed.
