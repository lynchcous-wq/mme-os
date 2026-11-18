# Build 011.22.4 — Self-service identity unlock request endpoint

## Implementation

Added `POST /api/identity/unlock-requests` on branch `build-01122-customer-auth-foundation`.

The route:
- Requires same-origin JSON POST.
- Requires a verified Supabase session and confirmed email.
- Derives the MME identity from the authenticated Supabase subject; ignores client-supplied identity IDs and status fields.
- Requires a reason between 10 and 1,000 characters.
- Looks up the caller's own identity and only accepts requests when that identity is not active.
- Checks for an existing pending self-request before inserting.
- Inserts only `target_identity_id`, `requested_by_identity_id`, `reason`, and `status='pending'`.
- Uses the server-only service role key; never returns credentials.
- Does not approve, reject, unlock, or update identity security status.

## Important limitations / release gates

- The pre-insert duplicate check is not atomic. Concurrent duplicate submissions remain possible until a partial unique index or transaction-backed RPC is reviewed and added.
- This route currently supports self-service requests only. It does not permit staff to request on behalf of another identity.
- No rate limiter is present yet. Add an abuse-control strategy before enabling this route in production.
- There is no UI entry point yet; this is API foundation only.
- No request submission has been executed against production and no database migration was run.
- The route currently reads the target identity even if its security status is locked, which is required for a locked user to submit a self-request.
- The request decision remains unavailable. A dedicated SECURITY DEFINER function and permission-checked reviewer interface are still required.

## Test and deployment status

The repository package scripts expose `next build` and `tsc --noEmit`, but no unit/integration test runner is configured. The current Vercel checks for commit `7816958b75df90bdee1afb34ff3b22b5207426d8` were pending at inspection. Do not treat the endpoint as verified until the preview build completes and request tests run against an isolated Supabase environment.

## Required tests

1. Reject missing/invalid origin, wrong content type, anonymous session, unconfirmed email, malformed reason, and oversized reason.
2. Reject missing/ambiguous identity and active identity.
3. Accept a locked identity with a confirmed authenticated session.
4. Ignore forged target/requester/status/approver fields in browser payload.
5. Return already-pending response for repeat request.
6. Verify no direct browser table grants are introduced.
7. Verify service-role key never enters client bundles or responses.
8. Verify duplicate concurrent requests are prevented after atomic deduplication is implemented.
9. Verify rate limiting before production exposure.

No approval or unlock operation is implemented by this route.
