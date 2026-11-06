# Build 010.00 — Warranty Security Operations Command Center

## Delivered
- Executive security metrics RPC.
- Authenticated dashboard API restricted to CEO, privacy officer and manager roles.
- CEO-only overdue-alert escalation action.
- Dashboard snapshot table with request correlation.
- Alert status and severity KPIs, including overdue open alerts.
- Notification queue, provider-accepted, delivered, failed and skipped metrics.
- Provider receipt counts and unmatched receipt visibility.
- Dashboard UI at `/warranty/security-dashboard`.
- Contract tests and CI workflow.

## API
- GET `/api/warranty/security-dashboard` — requires a valid Supabase bearer token and approved app_metadata role.
- POST `/api/warranty/security-dashboard/escalate` — CEO role only; invokes the existing overdue escalation routine.

## Boundaries
Metrics are refreshed on demand, not streamed. This increment does not implement incident case management, evidence storage, real-time subscriptions, or scheduled escalation. Provider-accepted messages are not counted as confirmed delivered. Snapshot rows are created when the dashboard summary RPC is called.

## Validation and rollout
Run `npm run lint` and `npm run test:build010:warranty-security-operations-dashboard`. Apply migrations in order in staging, verify source tables and role claims, then test access controls, metric accuracy and CEO escalation. No production migration replay, CI execution, deployment or live data verification is claimed.
