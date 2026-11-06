# Build 009.74 — Warranty Renewal & Retention Engine

## Scope
Adds governed renewal campaigns, 30/60/90-day opportunity records, pricing snapshots, customer decisions, renewal orders, payment-attempt tracking and retention facts.

## Eligibility and offers
Only active warranties with verified coverage end dates are candidates. Re-evaluate lifecycle state, cancellations, transfers, prior renewals, product/provider terms and campaign window before presenting an offer. Opportunity creation is idempotent per warranty and horizon. Campaigns and pricing rules require approval and versioning.

## Pricing integrity
Snapshots preserve product cost, service reserve, provider cost, customer price, currency, margin and pricing-rule version. Missing costs must remain unknown rather than silently treated as zero. Do not mix currencies. Forecasted retention and projected margins remain distinct from actuals.

## Customer acceptance and payment
Offers are not orders. A renewal order can be created only after an authenticated customer decision accepts a specific approved offer and records the terms version, evidence reference, channel and actor. No automatic charge is permitted from an expiration reminder, campaign eligibility or offer presentation. Payment requires an explicit order and supported payment-provider authorization; do not store PAN or CVV. Payment success requires verified provider evidence and idempotent reconciliation.

## Failed payment and retention
Track payment states and provider references; retry only according to approved payment policy and customer authorization. Do not create duplicate charges. Retention metrics must preserve cohort period, eligible/presented/accepted/converted counts, source provenance and actual-versus-projection classification.

## Security
All tables use RLS with browser grants revoked. Server-side APIs must derive customer identity from the authenticated session, enforce ownership and executive/finance role scope, audit offer approval and export actions, and protect payment references. Acceptance evidence and decision history are append-only.

## Validation
Run npm run lint and npm run test:build009:warranty-renewal. Add PostgreSQL integration tests for horizon boundaries, cancelled/transferred/expired exclusions, offer version drift, duplicate acceptance, cross-customer access, payment retries/idempotency, currency isolation and no-charge-before-acceptance.

## Rollout boundary
Schema and contract tests only. No scheduled opportunity worker, pricing calculator, customer renewal UI, payment-provider adapter, subscription linkage, actual renewal sale, production migration replay or deployment is claimed.
