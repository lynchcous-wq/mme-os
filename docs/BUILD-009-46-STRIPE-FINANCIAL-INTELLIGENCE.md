# Build 009.46 — Stripe Financial Intelligence & Predictive Reconciliation

## Purpose
Provide Finance and CEO users with repeatable, explainable risk snapshots based on imported Stripe settlement records and the Build 009.45 exception ledger.

## Model boundary
The first version is an explainable deterministic rules model (`explainable_rules_v1`), not a trained machine-learning model. It does not claim a guaranteed forecast or infer confirmed fraud/loss. It compares the selected 30-day window with the preceding 30 days and records its evidence, observed values and baselines.

## Signals
- Open/recently detected settlement exception volume.
- Delayed or still-unsettled Stripe batches relative to expected arrival.
- Unresolved exception exposure, grouped by ISO currency.
- Refund exception count relative to imported refund-line volume.
- Risk score from 0–100 with low, moderate, high and critical bands.

Amounts are integer minor units. Values from different currencies must never be summed. Exposure is not a confirmed loss. Low sample sizes must be interpreted cautiously.

## Recommendations
The engine may recommend Finance review of open exceptions, delayed settlements or elevated risk. Recommendations are immutable snapshots and do not issue refunds, change ledger facts, alter settlement batches, initiate payouts, or move money.

## Human decisions
A store-authorized Finance user may acknowledge, assign to an active employee, resolve or dismiss a recommendation with a documented reason. Critical recommendation closure requires the separate settlement approval permission. Decisions are append-only.

## Data access
RLS enabled on all intelligence tables. Client roles receive no direct access. Service-role operations are granted only through the protected RPCs and dashboard view.

## RPCs
- `mme_pos_build_stripe_financial_intelligence(location_id, actor_person_id, as_of_date, currency)`
- `mme_pos_record_stripe_financial_intelligence_decision(recommendation_id, actor_person_id, action, reason, assignee_person_id)`

## Validation
Run `npm run lint`, `npm run test:build009:stripe-financial-intelligence`, plus the Stripe refund settlement, settlement integrity and financial reporting suites. Replay migrations in order and run PostgreSQL tests for currency isolation, empty/small samples, baseline comparisons, duplicate run behavior, authorization, critical approvals, active assignees, immutable snapshots and decision audit.

## Rollout boundary
Implementation branch only. No production migration, automated schedule, external AI model, live provider action or dashboard deployment is claimed. This version uses explainable rules as a safe baseline; any later statistical or ML model must be separately validated, versioned and monitored before use.
