# Build 010.13 — Notification Provider Failover & Health Monitoring

## Delivered
- Provider health probe history with latency, status and error telemetry.
- Per-provider failure/recovery thresholds, priority and average latency.
- Database circuit-state transitions: closed, open and half-open.
- Health recorder RPC with service-role-only execution.
- Failover provider selection excludes disabled and open-circuit providers.
- Selection orders eligible providers by priority, latency and stable name.
- Authenticated operator API for health views and failover route previews.
- Secret-protected health probe ingestion endpoint.
- Provider health dashboard, contract tests, CI and rollout documentation.

## Dashboard
`/warranty/security-intelligence/providers/health`

## Worker integration
A separately deployed health-monitor worker must probe configured provider endpoints and submit authenticated outcomes using `MME_NOTIFICATION_HEALTHCHECK_SECRET`. A notification adapter may request a failover candidate through the provider-selection RPC. Health probes should be independent of customer message delivery and must respect provider terms, rate limits and credential boundaries.

## Important limitations
- No email/SMS/push/pager provider is connected or probed by this change.
- No scheduled health-check worker, automatic dispatch failover worker, outage notification fanout, or provider-specific rate limiter is provisioned.
- Circuit state is updated when authenticated probe results are recorded; the database does not run probes itself.
- The half-open recovery behavior requires the monitoring worker to continue submitting successful probes; it is not an autonomous timer.
- Failover selection is a routing primitive only. The adapter must send, handle provider idempotency, verify provider responses and record delivery receipts.
- No live migration, tests, CI run, external delivery or production deployment is claimed.

## Validation
Run `npm run lint` and `npm run test:build010:notification-provider-failover-health-monitoring`. Stage repeated failures, half-open recovery, latency ranking, disabled providers, simultaneous probes, stale telemetry and provider outages.
