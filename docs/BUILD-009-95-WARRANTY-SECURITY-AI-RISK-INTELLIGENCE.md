# Build 009.95 — Warranty Security AI Risk Intelligence

## Delivered
- Explainable security risk-signal ledger with constrained signal categories, severity, confidence and weight.
- Case-level risk read model with bounded score, contributing signals and unreviewed/high-severity counts.
- Human review states: unreviewed, accepted, dismissed and needs context.
- Append-only review history with reviewer, prior/new state, rationale and request correlation.
- Authenticated role-checked risk read and review API.
- Row-level security, service-role-only database access, contract tests and operational notes.

## API
GET /api/warranty/security-risk-intelligence?limit=50
POST /api/warranty/security-risk-intelligence
Body: { "signalId": "<uuid>", "status": "accepted|dismissed|needs_context", "note": "Reasoned review note" }

Reads require an authenticated MME app role. Reviews require CEO, privacy officer or manager role and a written rationale.

## Scoring and safety boundary
This increment provides a transparent weighted aggregation of explicitly recorded signals. It does not itself run a machine-learning model, infer employee intent, identify a repeat offender, automatically ingest signals from source systems, or make disciplinary recommendations. Scores are triage aids, not findings of misconduct or fraud. Confidence and weights must be calibrated and governed before operational use. A human reviewer remains responsible for decisions.

No employee-facing adverse action, account suspension, case closure, legal conclusion or notification is triggered by a score. Signal generation adapters, anomaly baselines, alert delivery and dashboard UI are future increments.

## Rollout
No production migration replay, data backfill, model training, source-system integration or deployment is claimed. Validate underlying case/evidence schema, RLS and role claims in staging. Ensure database roles and service-role credentials are not exposed to clients.

## Validation
Run `node --test tests/build009-warranty-security-ai-risk-intelligence.test.mjs` and `npm run lint`. Integration-test role boundaries, signal creation provenance, dismissed-signal exclusion, review concurrency, audit immutability and API error handling.
