# Build 009.85 — Warranty API Audit & Rate-Limit Protection

## Delivered
- Append-only compliance API audit table.
- Request correlation UUIDs returned in body and X-Request-ID header.
- Server-side audit recording for invalid sessions, invalid resources, denied roles, rate-limited calls, upstream failures and successful reads.
- SHA-256 digests for IP and rate-limit bucket identifiers; raw IP values are not persisted.
- Atomic database-backed fixed-window rate-limit RPC.
- Per-user limit: 60 requests per 60 seconds.
- Per-IP limit: 180 requests per 60 seconds.
- Fail-closed behavior if rate-limit infrastructure is unavailable.
- RLS, service-role-only RPCs, contract tests, CI and operational documentation.

## Security notes
The route trusts x-forwarded-for / x-real-ip only when supplied by a trusted reverse proxy that overwrites client-provided values. Configure the hosting proxy accordingly; otherwise IP-level limiting may be spoofable. The digest is not encryption and should be treated as pseudonymous data. Keep retention and access to audit data restricted.

The current fixed-window limiter is shared across application instances through Postgres. Rate bucket cleanup/retention and alerting thresholds require an operational maintenance job. This build does not add a dedicated dashboard for audit events or a distributed cache limiter.

## Validation
Run npm run lint and npm run test:build009:warranty-api-audit-rate-limit. Integration tests must validate concurrent atomic increments, exact window boundaries, spoofed forwarding headers, invalid/expired sessions, role denial, rate-limit failure, audit persistence and append-only permissions.

## Rollout boundary
Migration, route hardening and contract tests only. No production migration replay, trusted proxy configuration, cleanup schedule, SIEM integration, notification delivery or deployment is claimed.
