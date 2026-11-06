# Build 009.87 — Warranty Security Detection Worker

## Delivered
- Detection ledger with unique event/rule pair to prevent duplicate incident creation.
- Worker-run health records and bounded batch execution.
- Threshold evaluation against enabled event-type rules and event occurrence counts/window.
- Automatic incident creation with severity mapping.
- Append-only incident timeline event on successful detection.
- Service-role-only database RPC.
- Secret-protected internal POST endpoint at /api/internal/warranty-security-detection.
- Contract tests and CI.

## Trigger and scheduling
A trusted scheduler must POST to the internal endpoint with Authorization: Bearer <MME_SECURITY_WORKER_SECRET>. Configure the secret only in server-side deployment settings. Do not expose it through NEXT_PUBLIC variables. This repository change adds the endpoint but does not configure a schedule or prove that it is running. Start with a conservative cadence (for example, every minute) only after validating event volume, rule windows and alert ownership.

## Detection semantics and limitations
This first worker evaluates grouped occurrence_count and last_seen_at against configured thresholds; it does not reconstruct every individual event timestamp in a sliding window. Threshold rules must be configured by a trusted administrative process. Duplicate event/rule detections are suppressed by a unique key. Failed worker runs are recorded with a generic error code. Automated incident creation does not block users, disable accounts or block IPs.

## Validation
Run npm run lint and npm run test:build009:warranty-security-detection-worker. Integration tests must cover threshold boundary behavior, concurrent runs, idempotency, incident severity mapping, failure recovery, service-role access and invalid scheduler secrets.

## Rollout boundary
Migration, internal endpoint, contract tests and docs only. No scheduler configuration, production secrets, migration replay, monitoring dashboard, notification delivery or deployment is claimed.
