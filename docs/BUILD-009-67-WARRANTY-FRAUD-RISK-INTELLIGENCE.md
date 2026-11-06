# Build 009.67 — Warranty Fraud & Risk Intelligence

## Scope
Adds explainable warranty risk rules, assessment snapshots, signal evidence, human investigations, evidence verification, decisions and immutable audit events. It extends the warranty repair and financial workflows without replacing compliance, HR investigations or provider claim adjudication.

## Risk model
Risk scores are triage prioritization only. Rule weights and effective dates are versioned. Signals include repeat repairs on the same serialized unit, duplicate provider claim references, missing diagnostic records and unapproved labor entries. Provider anomaly and serial anomaly rules can be configured as future rules once authoritative source data and validated thresholds exist. No protected traits, inferred sensitive attributes, customer demographics or employee productivity proxies may be used.

## Human review
A risk score does not prove fraud. It must not automatically deny coverage, cancel a warranty, withhold a payment, reduce employee compensation or trigger discipline. Authorized reviewers inspect source evidence, document their reasoning and choose an auditable resolution. Adverse customer or employee action requires separate policy, legal/compliance review and applicable appeal process.

## Evidence integrity
Evidence records retain source references, content hashes, verifier and status. Binary evidence stays in approved encrypted object storage; do not store raw identity documents, payment data or unnecessary device identifiers in this database. Verify provenance, access logs and retention rules.

## Security
RLS on all new tables; no browser access. Service-role RPCs must be called only through authenticated APIs that enforce role, location, case ownership and separation of duties. Audit events are append-only. Restrict rule administration to compliance/risk administrators.

## Validation
Run npm run lint, npm run test:build009:warranty-risk, and existing warranty-repair, warranty-financial, communications and compliance suites. PostgreSQL integration tests must cover repeated repair detection, claim-reference collisions, false positives, evidence verification, unauthorized reviewer access, duplicate investigations and audit immutability.

## Rollout boundary
Draft implementation only. No production migration replay, live AI model, provider integration, automated adverse decision, HR disciplinary workflow or deployment is claimed.
