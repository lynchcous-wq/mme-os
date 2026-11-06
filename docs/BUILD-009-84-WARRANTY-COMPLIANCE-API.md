# Build 009.84 — Warranty Compliance API & Authorization

## Delivered
- Next.js GET route at /api/warranty/compliance.
- Supabase Auth bearer-token verification before data access.
- Fixed allowlist of five compliance resources: summary, calendar, approvals, alerts and assignments.
- Server-side role checks using trusted Supabase app_metadata claims.
- Server-only service-role key usage; no service credential is returned to clients.
- No-store responses, generic errors and a 500-row response cap.
- Contract tests, CI workflow and security notes.

## Role matrix
- CEO: all five resources.
- Privacy officer: all five resources.
- Manager: all five resources.
- Warranty specialist: calendar and alerts only.
- All other roles: denied.

## Important security boundary
This API is a first authorization layer, not a complete production security certification. The service-role key bypasses Supabase RLS, so every request must pass the application role gate before the service query. The API currently trusts roles only from Supabase app_metadata, which must be writable exclusively by trusted administrative/server processes, never by user-editable metadata. Do not place the service key in NEXT_PUBLIC variables or browser bundles.

The current route does not implement distributed rate limiting, per-user audit persistence, HR-backed department mapping, customer/tenant row scoping, or pagination cursors. Those must be completed before broad production exposure. In particular, the current compliance views are global aggregates and are intended for authorized internal staff, not customer-facing use. Use a server-side rate-limit provider and append-only audit sink in the next hardening step. Verify that the existing Supabase project has the referenced views and grants before deployment.

## Validation
Run npm run lint and npm run test:build009:warranty-compliance-api. Integration tests must cover invalid/expired tokens, role claim tampering resistance, every role/resource combination, missing environment configuration, upstream errors, response limits and no-cache headers.

## Rollout boundary
API route and contract tests only. No frontend dashboard, distributed rate limiter, persistent access-audit sink, HR integration, production secrets configuration, migration replay or deployment is claimed.
