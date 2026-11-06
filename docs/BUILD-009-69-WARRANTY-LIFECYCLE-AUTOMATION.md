# Build 009.69 — Warranty Lifecycle Automation
Adds warranty lifecycle records, event history, durable job and customer-notification outboxes, renewal offers, ownership transfers, cancellation requests, versioned eligibility snapshots and repair/replacement reviews.

Registration must be anchored to a serialized warranty and purchase reference. Provider registration is queued, not assumed accepted; activation requires verified coverage terms/provider confirmation. Expiry calculations must respect policy time zones and coverage boundaries.

Customer notifications must honor verified contact preferences, consent, opt-outs, quiet hours and suppression rules. Marketing renewal offers are separate from transactional notices and require approved terms and explicit customer acceptance.

Transfers require identity verification and authorized approval before owner change. Cancellation requires contract and refund review; request submission does not itself cancel coverage or authorize a refund. Unknown eligibility routes to manual review. Repair/replacement recommendations are advisory and require an authorized human decision.

All tables use RLS and service-role-only backend access. Backend routes must enforce customer ownership, role scope and separation of duties. This is draft schema and contract coverage only; no POS event hook, portal UI, notification provider, live manufacturer sync, renewal sale, production migration replay or deployment is claimed.

Validation: npm run lint; npm run test:build009:warranty-lifecycle; existing warranty repair, financial, risk and provider integration suites. PostgreSQL integration tests still required for access controls, duplicate events, consent, transfer authorization, cancellation approval and expiry boundaries.
