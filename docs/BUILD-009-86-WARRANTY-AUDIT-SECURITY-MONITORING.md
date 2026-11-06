# Build 009.86 — Warranty Audit Security Monitoring

## Delivered
- Security event taxonomy: authentication failure, authorization denial, rate-limit exceeded, API error, access anomaly and suspicious IP.
- Severity and lifecycle state.
- Idempotent event grouping by stable event key with occurrence counters and first/last seen timestamps.
- Security incident case records with owner, severity, containment/resolution lifecycle.
- Append-only incident timeline for investigation notes and state changes.
- Versioned monitoring threshold configuration.
- Security dashboard and incident queue read models.
- Compliance API now records authentication failures, role denials, rate-limit events and API errors into the security event system.
- RLS, service-role-only access, contract tests, CI and documentation.

## Security and operational boundaries
This build records and groups events; it does not itself run a background detection scheduler, send notifications, block network addresses, or create incident tickets automatically. Monitoring rules are configuration only until a trusted scheduled evaluator is deployed. Event keys and IP digests are pseudonymous, not encrypted. Forwarded IP headers must be overwritten by a trusted hosting proxy. Incident notes must not contain passwords, bearer tokens, payment data or raw customer evidence.

The CEO/security cockpit and privacy officer reporting interface are not implemented in this build. Dashboard views are service-role-only read models and must be served through a separately authorized server route.

## Validation
Run npm run lint and npm run test:build009:warranty-audit-security-monitoring. Integration tests should cover event idempotency, role/resource boundaries, RLS, append-only incident events, incident lifecycle, rate-limit event thresholds, and trusted proxy configuration.

## Rollout boundary
Schema, API event recording, contract tests and CI only. No scheduled detector, notifications, IP blocking, production migration replay, external SIEM, dashboard UI or deployment is claimed.
