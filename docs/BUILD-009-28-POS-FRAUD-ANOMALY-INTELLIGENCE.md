# Build 009.28 — POS Fraud Detection & Transaction Anomaly Intelligence Engine

Status: implementation committed to a review branch; migration replay, PostgreSQL integration tests, rule calibration and payment/inventory connector validation pending.

## Reused foundation
- Build 009.20 hardware dispatch and idempotent command execution.
- Build 009.21 hardware acknowledgment and uncertain-outcome reconciliation.
- Build 009.22 device health and predictive diagnostics.
- Build 009.23 hardware fleet identity, store assignment and scoped administration.
- Build 009.25 network security and payment-terminal communication safeguards.
- Build 009.26 transaction continuity journal and payment reconciliation safeguards.
- Build 009.27 security events, investigations, evidence custody and shared authorization gate.
- Build 017 return/refund condition grading and serialized-item inspection are integration dependencies; this build does not replace that workflow.

## Implemented database foundation
- `mme_pos_fraud_rules`: versioned, approvable fraud/anomaly rules.
- `mme_pos_fraud_events`: normalized store/register/transaction/payment/return/drawer/serial observations.
- `mme_pos_fraud_assessments`: explainable risk score, contributing factors, model/ruleset version and expiry.
- `mme_pos_fraud_cases`: human-reviewed case lifecycle and resolution state.
- `mme_pos_fraud_case_events`: event-to-case association.
- `mme_pos_fraud_evidence`: evidence references, digest, sensitivity and custody history.
- `mme_pos_fraud_reviews`: reviewer decisions and documented rationale.
- `mme_pos_fraud_outcomes`: approved outcome, loss/recovery amounts and corrective-action reference.
- `mme_pos_fraud_audit_events`: actor, action, reason and object audit trail.

## Detection coverage
The event model supports signals for:
- Repeated refunds, returns or voids; refund without a matching sale; unusual refund timing or tender differences.
- Unusual discount/price overrides, including patterns by role, register, item category, store and time.
- Excessive no-sale drawer openings or unusual drawer activity, correlated with the hardware event history.
- Duplicate processor references, repeated payment attempts, unusual decline velocity and suspicious split-tender patterns.
- Payment state conflicts, including a sale recorded as captured without a confirmed processor capture.
- Serial-number or IMEI mismatch, item substitution, inventory discrepancy and return-condition differences.
- Repeated return patterns linked to product, customer reference, register, employee or store.
- Unusual transaction velocity, amount distributions, time-of-day patterns and deviations from comparable baselines.

A rule/analytics worker must correlate the event stream with authoritative POS transactions, payment processor references, inventory records and Build 017 return/inspection records. The schema stores signals and outcomes; it does not yet implement a live streaming worker or calibrated statistical model.

## Risk scoring and alert thresholds
Risk scores are advisory and explainable. The initial display bands are:
- 0–19 informational
- 20–39 low
- 40–59 moderate
- 60–79 high
- 80–100 critical

Thresholds must be configurable by rule, store, tender, item category and operating context, then calibrated against historical outcomes. A high score does not establish fraud. Declines, authorization-only transactions, legitimate voids, approved discounts and ordinary returns must not be labeled fraudulent without corroborating evidence.

## Human investigation workflow
1. Trusted connectors ingest normalized events using an idempotent event key.
2. A rule/statistics worker evaluates approved, enabled rule versions and creates an explainable assessment.
3. A case manager or authorized reviewer opens a case and links relevant events.
4. Investigators collect approved evidence: transaction/receipt references, processor references, item/serial test records, return-condition records, register/drawer logs and approved camera references.
5. A reviewer records a decision and rationale. Cases may remain under review, be found inconclusive, unsubstantiated or false positive, or be escalated to an authorized final outcome approver.
6. Outcomes record confirmed loss/no loss, policy gap, training gap, processor referral or other permitted resolution, with loss/recovery values where supported.

## MME-specific integrations
- POS and processor: reconcile processor authorization, capture, reversal, refund and chargeback references before classifying a payment anomaly. Use processor tokens/references only.
- Returns/refunds: link Build 017 inspection results, condition grades, defects, photos/evidence references and warranty decisions. Do not duplicate or bypass the returns authorization policy.
- Serialized electronics: compare item serial/IMEI references across receiving, inventory, sale and return. Store only masked serial/IMEI in the anomaly event unless a separately authorized encrypted source record is required.
- Cash drawer: correlate no-sale opens, dispatch/acknowledgment status and physical drawer state from Builds 009.20–009.22. A timeout alone is not evidence of misconduct.
- Inventory: compare the sold/returned item identity and stock movement using authoritative inventory records; do not infer loss from stale or delayed synchronization.

## Payment, customer and employee safeguards
- Never store PAN, full card number, CVV/CVC, PIN, magnetic-stripe/track data or unmasked cardholder authentication data. Use processor references/tokens.
- A decline or authorization is not a captured payment. An uncertain payment outcome must be reconciled with the processor before retry.
- Do not automatically block customers, cancel sales, withhold legitimate refunds or discipline employees solely from a score or alert.
- High-risk refunds may be routed to a human review step only where the published return policy and legal requirements permit it. Keep a clear escalation path and record the reason.
- Separate fraud investigation from HR disciplinary decisions. Employee-related cases require corroboration, authorized review and a separate HR process.
- Minimize customer/employee identifiers, restrict case evidence by role and assignment, and enforce retention/legal-hold policy.

## Security and permissions
- All new tables enable RLS; direct public/anonymous/authenticated access is revoked; service-role access is granted for trusted workers.
- The shared Build 009.27 hardware authorization gate is extended to recognize `pos.fraud.view`, `pos.fraud.review`, `pos.fraud.rules.manage`, `pos.fraud.case.manage` and `pos.fraud.override` while preserving active identity, active employment, CEO freeze, grant expiry and location scope checks.
- Rules require explicit approval before activation.
- Event ingestion is idempotent and rejects sensitive payment-card keys in the details payload.
- Case creation checks that linked events belong to the same store.
- Case review and final outcome are separate operations; final outcomes require an authorized approver and create audit records.

## Dashboard specification (not live)
- CEO: enterprise fraud trends, confirmed loss/recovery, store comparisons and escalated cases; restricted evidence access.
- CIO / IT: event connector health, data quality, duplicate/reconciliation queues and technical anomalies.
- Loss Prevention Manager: assigned cases, evidence, case aging, investigation status, outcomes and no-evidence/unsubstantiated resolutions.
- Store Manager: limited local exception queue and policy-approved actions; no unrestricted employee/customer case history.
- Finance: processor reconciliation, confirmed loss/recovery and chargeback status; token/reference only, no raw card data.

## Validation required
Run:
- `npm run test:build009:fraud-intelligence`
- `npm run test:build009:security-intelligence`
- `npm run test:build009:disaster-recovery`
- `npm run test:build009:network-security`
- `npm run test:build009:firmware-orchestration`
- `npm run test:build009:hardware-fleet-administration`
- `npm run test:build009:hardware-health-intelligence`
- `npm run test:build009:hardware-ack-reconciliation`
- `npm run lint`
- Full ordered Supabase migration replay and PostgreSQL integration tests in an isolated environment.

Integration tests must cover duplicate events, event-key collision across stores, sensitive card-data rejection, unapproved rules, disabled rules, out-of-range risk score, mismatched store event linkage, unauthorized reviewer, unauthorized outcome approver, false-positive closure, loss/recovery arithmetic, processor reconciliation and serial/IMEI mismatch evidence. Rule calibration must include false-positive/false-negative review using representative historical data before production activation.

## Not claimed complete
No migration has been applied to production Supabase. No live Stripe/Verifone connector, chargeback feed, inventory/returns connector, streaming rule worker, statistical/ML model, case dashboard or customer refund hold has been deployed. No transaction has been classified as fraudulent. No employee disciplinary action or customer restriction is triggered by this build.
