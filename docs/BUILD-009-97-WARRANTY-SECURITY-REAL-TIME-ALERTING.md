# Build 009.97 — Warranty Security Real-Time Alerting

## Delivered
- Alert queue automatically populated when a risk signal is inserted.
- Severity-based routing: high/critical to CEO, privacy officer and manager; lower severity to CEO and privacy officer.
- Acknowledgment deadlines: critical 5 minutes, high 15 minutes, medium 4 hours, low 24 hours.
- Alert acknowledgment, resolution and dismissal actions with required written rationale for closure.
- Event history and request correlation.
- Escalation routine for overdue open alerts, adding CEO and privacy officer routing.
- Authenticated alert queue/action APIs and privileged escalation API.
- In-app alert console at /warranty/security-alerts with severity counts.
- Contract tests and operational documentation.

## Endpoints
- GET /api/warranty/security-alerts?limit=50
- POST /api/warranty/security-alerts with { "alertId": "<uuid>", "action": "acknowledged|resolved|dismissed", "note": "..." }
- POST /api/warranty/security-alerts/escalate

## Delivery boundary
This increment queues in-app notifications and records delivery rows. It does not deliver external email, SMS or webhooks; provider credentials and delivery workers are not configured. Escalation is manually invoked by CEO/privacy officer; no scheduler or realtime push subscription is enabled. The console refreshes on demand.

## Security and rollout
RLS is enabled and direct client table access is revoked. APIs validate Supabase sessions and roles. Validate schema dependencies, app_metadata role claims, RLS, queue visibility, escalation timing and concurrent actions in staging. No production migration replay or deployment is claimed.
