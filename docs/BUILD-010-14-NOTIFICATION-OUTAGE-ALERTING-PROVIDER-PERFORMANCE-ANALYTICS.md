# Build 010.14 — Notification Outage Alerting & Provider Performance Analytics

## Delivered
- Idempotent provider outage history keyed by provider and outage event.
- Outage severity, detection, observation count and recovery timestamps.
- Authenticated monitoring-worker outage event and recovery API.
- 30-day health-probe success percentage and p95 latency analytics.
- 30-day outage counts and last-outage reporting.
- Separate lateral aggregates prevent probe/outage join multiplication.
- RLS-protected outage ledger and service-role-only RPCs.
- CEO/CIO/IT/privacy-role analytics API and executive dashboard.
- Contract tests, CI workflow and rollout documentation.

## Dashboard
`/warranty/security-intelligence/providers/analytics`

## Monitoring integration
A trusted monitoring worker must evaluate provider probe telemetry against configured thresholds, create an outage event once, update observations idempotently, and report recovery after the configured recovery policy is satisfied. It must also trigger leadership notifications through the notification delivery system with deduplication and escalation rules.

## Important limitations
- This build records outage events; it does not run provider probes or automatically detect outages.
- CEO/CIO notifications, escalation fanout and recovery messages are not dispatched by this build.
- Analytics are based on health probes, not confirmed customer message delivery receipts.
- No SLA target, alert threshold, probe cadence or provider service agreement is assumed.
- No external provider integration, scheduled worker, migration execution, test/CI execution or production deployment is claimed.

## Validation
Run `npm run lint` and `npm run test:build010:notification-outage-alerting-provider-performance-analytics`. Stage duplicate outage keys, recovery idempotency, no-probe samples, provider-specific channel aggregation, high-volume probe history and outage event replay.
