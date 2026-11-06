# Build 009.88 — Warranty Security Escalation & Notifications

## Delivered
- Notification recipient registry for CEO, privacy officer and manager roles.
- Per-severity escalation policies with initial delay, repeat interval, recipient roles and bounded attempt count.
- Idempotent notification outbox keyed by incident, recipient and template.
- Email/SMS channel metadata and templates for opened, escalated, acknowledged and resolved incidents.
- Provider-attempt ledger and delivery outcome states.
- Incident acknowledgement records; acknowledgement suppresses future queued escalation and cancels pending/retry notifications.
- Service-role-only notification enqueue RPC.
- Atomic due-notification claim RPC using row locks and SKIP LOCKED.
- Delivery finalization RPC with exponential retry delay and terminal failure state.
- Secret-protected internal enqueue endpoint.
- Contract tests and CI.

## Important delivery boundary
This build queues notifications and records delivery attempts; the internal endpoint currently enqueues only. A provider transport adapter (for example, a configured email and SMS service), verified sender identities, recipient consent/preferences, webhook verification, and production secrets must be configured before messages can be sent. No email or SMS has been sent by this change. No scheduler has been activated.

## Security
Keep recipient destinations and provider credentials server-side. Do not place credentials in NEXT_PUBLIC variables. Restrict notification recipient management to a privileged administrative workflow. Notification bodies contain only incident identifiers, severity and short titles; never include bearer tokens, payment data or raw evidence. Add rate caps and provider-specific compliance/opt-out handling before enabling SMS.

## Validation
Run npm run lint and npm run test:build009:warranty-security-escalation-notifications. Integration tests must cover role routing, severity thresholds, duplicate suppression, concurrent claims, retry exhaustion, acknowledgement cancellation and RLS.

## Rollout boundary
Schema, enqueue/claim/finalize primitives, protected enqueue endpoint, tests and documentation only. No provider transport, production secrets, schedule, migration replay, external delivery or deployment is claimed.
