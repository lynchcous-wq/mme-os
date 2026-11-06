# Build 010.08 — Security Integration Observability & Alerting

## Delivered
- Time-series integration metric table.
- Alert policy and alert lifecycle tables.
- Default rules for delivery failures, latency, queue backlog, dead letters and open circuits.
- SQL alert evaluation function with duplicate-open-alert suppression.
- Source adapter records delivery failure metrics and invokes alert evaluation.
- Role-protected observability API for CEO, CIO, IT admin and privacy officer.
- Alert acknowledge and resolve actions.
- Executive integration observability dashboard.
- Contract tests and CI.

## Dashboard
`/warranty/security-intelligence/observability`

## Important limitations
- Only delivery failure metrics are currently emitted from the adapter in this increment. Success, latency, queue backlog, dead-letter and circuit metrics require additional producers before the related policies can trigger reliably.
- Alert evaluation is invoked from the failure path; it is not a scheduled continuous evaluator.
- External notification channels (email, SMS, pager), escalation timers, SLA calculations and retention/rollup jobs are not implemented.
- The metric sum shown for dead-letter records is a recent stored-metric sum, not a live dead-letter table count.
- Alert acknowledgement/resolution is role-gated but does not yet enforce assignment, mandatory resolution notes or immutable action history.
- This version reports stored observations and must not be represented as real-time uptime/SLA certification.
- No migration application, CI execution, deployment or live alert delivery is claimed.

## Configuration and validation
No new secrets. Run `npm run lint` and `npm run test:build010:security-integration-observability-alerting`. Stage metric producers, threshold boundaries, alert deduplication, role access, acknowledgement, resolution and notification escalation before production.
