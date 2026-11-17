# Build 011.24 — Customer Authentication Security Hardening

## Scope
Adds a shared, durable, fail-closed IP-based rate limiter to customer sign-in, customer registration, and email-confirmation session exchange. Existing employee authentication and customer activation rules are unchanged.

## Implementation
- Shared helper: `lib/security/auth-rate-limit.ts`.
- Storage: Upstash Redis REST using an atomic Lua fixed-window counter.
- Identifier privacy: client address is HMAC-SHA256 hashed with a private secret before becoming part of the Redis key. Raw client addresses are not persisted by this helper.
- Failure mode: if Redis, required secrets, or the trusted client address are unavailable, the endpoint returns a generic 503 and does not proceed with authentication.
- Limit response: generic 429 with `Retry-After` and `Cache-Control: no-store`.
- Request origin and JSON content-type checks remain in place.

## Endpoint thresholds
| Endpoint | Limit | Window |
|---|---:|---:|
| `POST /api/auth/customer-sign-in` | 10 attempts | 15 minutes |
| `POST /api/auth/customer-sign-up` | 5 attempts | 60 minutes |
| `POST /api/auth/customer-session` | 10 attempts | 15 minutes |

These are initial conservative per-client-address thresholds. Review with production traffic and provider-side Supabase Auth protections before launch. Add account/email-keyed throttling and bot mitigation as a separately reviewed enhancement; do not log raw email addresses or passwords.

## Required private environment configuration
Set these only as server-side Vercel environment variables for the appropriate preview and production environments:
- `UPSTASH_REDIS_REST_URL`: HTTPS REST endpoint for the dedicated MME rate-limit Redis database.
- `UPSTASH_REDIS_REST_TOKEN`: write-scoped token for that database only.
- `MME_RATE_LIMIT_HASH_SECRET`: cryptographically random secret of at least 32 characters; keep stable across instances and rotate through a planned key-version migration.

Never use `NEXT_PUBLIC_*` for these values. Do not reuse production credentials in preview. Use a separate preview database/token and secret. Ensure Redis key TTL expiry and access logging policies are reviewed. Do not put secrets in source control, build logs, client bundles, or documentation.

## Trust boundary
The helper reads the client address from `x-real-ip`, then `x-vercel-forwarded-for`, then the first `x-forwarded-for` entry. Before enabling this control in production, verify with the actual Vercel deployment/runtime that the selected header is set or overwritten by trusted infrastructure and cannot be supplied or spoofed by the requester. If no trusted address is available, requests fail closed. Do not deploy behind an unreviewed proxy configuration.

## Required tests before release
- Atomic counter increments across concurrent requests and serverless instances.
- Requests below threshold succeed; threshold+1 returns 429 and a valid Retry-After.
- Window expiry resets the counter.
- Distinct HMAC secret or client identifier produces isolated keys.
- Missing Redis URL/token/hash secret, short hash secret, malformed response, timeout, non-2xx, and missing trusted address all return generic 503.
- Raw IP, email, password, access token, and refresh token never appear in Redis keys or application logs.
- Origin rejection still returns 403; non-JSON still returns 415.
- Registration, sign-in, and confirmation each use the intended bucket and threshold.
- Employee sign-in is unaffected.
- Supabase provider-level throttling and CAPTCHA/bot mitigation are configured and tested independently.

## Verification and release status
- [x] Shared limiter added.
- [x] Customer sign-in endpoint wired to limiter.
- [x] Customer registration endpoint wired to limiter.
- [x] Confirmation session endpoint wired to limiter.
- [ ] Confirm trusted client IP header behavior on Vercel.
- [ ] Provision dedicated preview Redis and private preview secrets.
- [ ] Add and pass automated unit/integration/security tests.
- [ ] Configure provider-side abuse protection and assess CAPTCHA/bot mitigation.
- [ ] Confirm no sensitive values appear in logs or client bundles.
- [ ] Re-run typecheck, production build, and preview end-to-end tests.
- [ ] Obtain explicit production release approval.

## Deployment decision
**HOLD — not production ready.** This change does not configure secrets, provision Redis, merge PR #200, alter the production database, or deploy to production. Fail-closed behavior means customer sign-in/registration/confirmation will return 503 until the required private environment values and Redis service are correctly provisioned.
