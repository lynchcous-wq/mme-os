# Build 010.78 — Warranty & Service Automation

## Implemented
- Configurable SLA policy records for warranty claims, repairs and RMAs, with response, resolution and escalation thresholds.
- Default standard policies are seeded conservatively and are operational defaults, not approved contractual promises.
- Expiry reminder candidate generation at 90, 60, 30 and 7 days before active warranty expiration.
- SLA overdue candidate generation for open warranty claims, repairs and RMAs.
- Notification outbox with unique idempotency event keys, queued/leased/sent/failed/cancelled/suppressed states, retry metadata and payload.
- Automation run history and counts.
- Authenticated operations API and service automation dashboard.
- RLS and service-role-only database function execution.

## Safety and release boundaries
- Dispatcher only creates queue records. It does not send email, SMS or in-app customer messages.
- No email/SMS provider credentials, customer consent checks, delivery receipts, bounce handling or provider failover are configured.
- A scheduled cron trigger is not installed; an authorized operator must run the dispatcher until scheduling is configured.
- SLA policy defaults require management review and do not constitute contractual SLAs.
- Expiry events are generated only on the exact 90/60/30/7-day dates when the dispatcher runs; missed-day backfill is not included.
- The current SLA candidate logic uses record creation/submission timestamps and standard policy thresholds; acknowledgement-time and pause/business-hours calendars are not modeled.
- No warranty renewal sales workflow or predictive fraud scoring is included.

## Validation
Run `npm run test:build010:warranty-service-automation`, warranty/claims/repair/RMA and notification suites, `npm run lint` and `npm run build`. Tests not executed; migration not applied; not merged or deployed.
