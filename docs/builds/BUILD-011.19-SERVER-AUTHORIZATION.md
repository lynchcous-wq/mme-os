# Build 011.19 — Server-Side Authorization Engine

Status: database authorization evaluator applied; fail-closed checks verified. No account was activated and no live grants were issued.

## Enforcement model
`public.mme_authorize(resource_key, action_key, target_identity_id)` is a read-only **SECURITY INVOKER** function. It returns true only when all required conditions hold:
- A valid authenticated Supabase user exists.
- JWT session ID maps to a current row in `auth.sessions` for that user.
- Session has not passed `not_after`.
- MFA assurance is `aal2` when required by the template.
- JWT issued-at time is within 10 minutes (with 60 seconds of clock-skew allowance) when recent authentication is required.
- MME person identity is active and linked to `auth.uid()`.
- Employee relationship is active.
- Role definition is active.
- Role assignment is active and within its effective dates.
- A matching permission grant exists and is active.
- The matching permission template is approved.
- Both assignment scope and grant scope contain the template's required scope.
- Self-target restrictions are enforced.

An action whose template requires secondary approval is denied unconditionally in this build. CEO unlock is therefore not available until a separate two-person approval workflow is implemented.

## Privileged helper hardening
- Created non-exposed `private` schema.
- Moved `mme_prepare_ceo_provisioning(text,text)` from `public` to `private`; execution remains restricted to `service_role`.
- Added `private.mme_session_is_active()`, a no-argument SECURITY DEFINER helper that checks only the caller's own JWT session against `auth.sessions`.
- Both private functions use an empty search path and explicit schema qualification.
- The public authorization evaluator is SECURITY INVOKER and is callable only by authenticated/service_role, not anon/PUBLIC.

## RLS
The permission-template table remains RLS enabled. Authenticated users receive SELECT only, and the SELECT policy exposes approved templates only for their own active role. No client write grants or policies were added.

## Audit requirement
The evaluator itself is read-only. Every protected mutation must be wrapped by a trusted server route that records the allow/deny outcome and the resulting business action in the append-only `mme_identity_audit_events` table using a server-only credential. A client must never submit its own audit outcome. This build does not claim application routes are integrated until route coverage tests pass.

## Verification limits
The live Auth user count is zero, so successful AAL2/active-session/employee/grant paths cannot yet be exercised with a real user. SQL checks verify fail-closed behavior for unauthenticated context, grants, RLS and function security. End-to-end allow/deny tests remain blocked until a verified test account and fixture records exist.

No Vercel deployment was made.