# Build 010.80 — Secure Account Sign-In Foundation

**Status:** Draft implementation; not merged, deployed, or production-validated.

## Scope
- Add a server-mediated Supabase password sign-in endpoint.
- Keep access and refresh tokens in HttpOnly, Secure-in-production, SameSite=Lax cookies; never return tokens to browser JavaScript.
- Add session inspection with server-side access-token validation and refresh-token rotation.
- Add sign-out that clears both session cookies.
- Add a separate employee authorization check. A valid login alone never confers employee permissions.
- Resolve employee access through the verified Build 004 person mapping and require an active employee relationship. Missing or unbackfilled person links fail closed.
- Enforce same-origin requests for sign-in and sign-out, JSON-only sign-in requests, bounded credential inputs, and no-store responses.

## Explicit non-goals / remaining work
- No customer or employee registration, password reset, MFA, passkeys, account linking, invite acceptance, or account recovery in this build.
- No customer relationship authorization endpoint or customer portal UI yet.
- No employee role/permission dashboard yet; this endpoint establishes only active employee relationship eligibility. Feature-specific APIs must still enforce grants and scope.
- No identity mapping, CEO provisioning, employee backfill, or Supabase migration is performed.
- No automatic email-based account linking.
- No cookies are set until Supabase authentication returns a valid token pair.

## Release gates
1. Configure Supabase URL, anon key, and service-role key as server environment variables; never expose service-role key with a NEXT_PUBLIC_ prefix.
2. Apply reviewed Build 004 identity migrations and complete verified account/person/employee mapping.
3. Add rate limiting at the edge or trusted API gateway; monitor credential stuffing and auth provider failures.
4. Test same-origin rejection, invalid credentials, access-token expiry, refresh rotation, revoked sessions, missing refresh token, and cookie flags.
5. Test customer and employee separation with synthetic identities; an employee termination must not delete the customer's account relationship.
6. Add registration, recovery, MFA and customer self-service flows before public launch.
7. Run full build, lint, unit/contract tests and a staging Supabase auth exercise before merge/deploy.

## Security notes
- Auth tokens are HttpOnly and not readable by browser JavaScript.
- SameSite=Lax is defense-in-depth, not a substitute for origin validation and rate limiting.
- Sign-out clears the browser's session cookies. Provider-side global session revocation is not performed by this endpoint.
- Employee access checks both the active person resolver and active employee relationship. The existing migration leaves person_id nullable until a separately verified backfill; therefore unlinked accounts are denied.
