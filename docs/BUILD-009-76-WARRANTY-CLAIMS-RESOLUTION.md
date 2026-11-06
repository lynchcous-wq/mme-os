# Build 009.76 — Warranty Claims Management & Resolution Center

## Delivered schema foundation
- Claim case records linked to verified warranty lifecycle and customer identity.
- Evidence metadata with content digest, storage reference, quarantine state and verification.
- Separate identity, purchase, serial, IMEI, coverage and fraud-review verification records.
- Provider submission/response references and payload digests.
- Proposed repair, replacement, refund or denial resolutions.
- Independent recommendation and approval identities, with second approver fields.
- Repair milestone events and append-only claim audit timeline.

## Workflow policy
A claim is not eligible merely because a customer submits it. Verify customer ownership, original purchase reference, serialized product identity and warranty coverage against authoritative records. Missing or conflicting evidence routes to manual review. Evidence files must be scanned and stored in private object storage; database records contain references and digests, not file contents.

Provider submission must use an approved provider adapter and idempotency key. Provider acknowledgement is not approval. Repair, replacement and refund execution must follow provider terms, company policy and separate POS/refund controls.

High-value replacement/refund thresholds must be configured by approved policy; do not invent thresholds in code. The recommender cannot approve its own resolution. A second approver is required where policy sets a dual-control threshold. Approval alone does not execute a refund or issue inventory.

## Security
All seven tables enable RLS and revoke browser-role grants. Server APIs must derive customer identity from the authenticated session, enforce customer ownership and staff role scope, rate-limit submissions, validate upload size/type, malware-scan files, and audit all status changes. Never expose serial/IMEI raw values in analytics; digests or masked representations only.

## Validation
Run npm run lint and npm run test:build009:warranty-claims. Add database integration tests for cross-customer access, evidence quarantine, duplicate submissions, verification provenance, approval separation, dual-control policy, provider idempotency and refund execution isolation.

## Rollout boundary
Database schema, contract tests and documentation only. No customer claim form, staff dashboard, upload service, malware scanner, provider API, refund executor, live workflow worker, production migration replay or deployment is claimed.
