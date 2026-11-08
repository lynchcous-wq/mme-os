# Build 011.10 — Authentication Consolidation Audit

Status: **existing implementation located; consolidation and security validation required before promotion**.
Branch: `implementation/build-011-10-authentication-consolidation`.
Base: `implementation/build-011-09-identity-access-foundation`.
Date: 2026-11-08.

## Executive finding

The prior Build 011.09 conclusion that identity/authentication source was absent from the repository was too narrow. The GitHub branch inventory reveals substantial earlier work in other branches. Build 011.10 therefore does not recreate sign-in or identity tables. It establishes a controlled consolidation path and records the code and database evidence that must be reconciled before any branch is promoted.

Relevant existing branches:
- `implementation/build-004-supabase-identity-foundation`
- `integration/build004-identity-validation`
- `implementation/build-010-83-customer-identity-linking`
- `implementation/build-010-84-identity-review-dashboard`
- `implementation/build001-authenticated-checkout-ui`

These branches are separate development histories. Their presence does not prove their code or migrations are deployed to the active production Supabase project or current production Vercel deployment.

## Existing implementation located

### Identity and database artifacts

The `integration/build004-identity-validation` branch contains:
- `supabase/migrations/20261103000100_identity_matrix_foundation.sql`
- `supabase/migrations/20261103000200_auth_identity_trigger.sql`
- `supabase/migrations/20261103000300_identity_audit_append_only.sql`
- `supabase/migrations/20261103000400_identity_security_lock.sql`
- `supabase/migrations/20261103000500_auth_trigger_execute_lock.sql`
- `supabase/migrations/20261103000601_identity_authorization_engine.sql`
- `lib/server/identity-authorization.ts`
- identity diagnostics and security review documentation.

The identity foundation migration defines person identities, separate customer and employee relationship records, role assignments, permission grants, integration entitlements, profile appearance preferences, role-color registry and audit events. The Auth trigger creates a person identity for a new Auth user. The authorization engine provides a server-only employee permission decision function.

The `implementation/build-010-84-identity-review-dashboard` branch contains later identity-related work, including:
- `lib/auth/supabase-session.ts`
- customer registration, sign-in, session, sign-out and email-verification routes;
- customer and employee access-check routes;
- customer identity-link request and employee review surfaces;
- additional Build 004 identity/authorization documentation;
- person-identity and authorization hardening migration filenames.

### Authentication code inspected

The existing `lib/auth/supabase-session.ts`:
- Calls Supabase Auth to validate access tokens and refresh sessions.
- Stores access and refresh tokens in HttpOnly cookies.
- Includes same-origin checking and a password sign-in helper.
- Includes an employee identity helper that resolves an Auth subject to a person ID and checks for an active employee relationship.

The existing customer route checks for a linked customer account and an active person identity. The employee route checks for an active employee identity. Registration requires a valid email, a 12–128 character password and a name; it intentionally does not create an authenticated session. Email verification discards the verification tokens and requires a normal sign-in. Customer linking is a separate review request, not automatic access.

## Security and correctness gaps to resolve before reuse

These are review findings from the inspected source files; they are not assertions about the live database.

1. **No production verification:** no live Supabase Auth settings, schema, RLS/policies, migration history or environment-variable presence was available through the inspected GitHub source.
2. **Migration drift:** the older identity foundation migration uses `mme_person_identities` with `auth_user_id`, `mme_customer_relationships`, and `mme_employee_relationships`. Later code refers to `mme_customer_account_links`, `mme_customer_identity_link_requests`, `employee_relationships`, and `mme_resolve_person_for_auth_subject`. Reconcile these names and data contracts before selecting migrations.
3. **Authorization parity:** the inspected employee access helper confirms an active employee relationship but does not itself call the action/resource/scope permission engine. Employee route guards must use the central authorization decision point for each protected action.
4. **Session revocation:** the inspected sign-out route clears browser cookies but does not call Supabase Auth to revoke the provider session or refresh token. Add provider-side revocation and server-side session invalidation according to the configured Supabase capabilities.
5. **Customer data minimization:** the customer access route returns an internal `personId`. Review whether the browser needs this identifier; default to returning only a minimal access summary.
6. **CSRF and origin checks:** ensure every state-changing cookie-authenticated endpoint, including customer-link requests and recovery flows, enforces a shared origin/CSRF policy. Validate malformed Origin headers safely.
7. **Abuse protection:** verify provider and application-level rate limits for registration, sign-in, email verification, recovery, and identity-link requests. Do not rely only on UI throttling.
8. **Cookie/session policy:** verify production-only Secure, HttpOnly, SameSite, path, expiry, refresh rotation and session revocation behavior. Confirm no token is returned to client JavaScript.
9. **Identity linking:** keep email verification separate from customer account linking. Link only after a trusted review/verification process with duplicate/conflict handling and immutable audit events.
10. **RLS and service-role use:** every service-role query must be narrow, server-only, input-validated and backed by server authorization. Direct browser access to private identity/link tables must be denied.
11. **Employee/customer separation:** tests must prove employee termination does not disable the customer relationship and customer restriction does not alter employment state.
12. **Error handling and logging:** use generic authentication errors, no-store responses and safe logs; never log credentials, access/refresh tokens, recovery tokens or unnecessary personal data.

## Consolidation plan

1. Treat Build 004 Identity Matrix as the authoritative design contract.
2. Select the most complete migration lineage only after comparing all SQL migration files and dependencies from the identity branches.
3. Compare the older identity schema with later person-keyed hardening migrations and current POS/catalog authorization consumers.
4. Reconcile RPC names and signatures, table/column names, RLS policies, grants, triggers, constraints and migration ordering.
5. Reuse the existing Supabase Auth adapter; do not introduce a second provider.
6. Consolidate authentication routes only after the shared session module passes security review and tests.
7. Replace active-employee-only guards with the central action/resource/scope authorization service where the endpoint requires a permission.
8. Add provider-side logout/revocation, common CSRF/origin protection, rate limiting, and minimum response fields.
9. Add integration tests for customer + employee relationship coexistence, employee termination/customer continuity, account linking, session expiry/revocation, permission denial and RLS.
10. Validate against a staging Supabase project and preview deployment. Do not apply migrations to production or promote a branch solely because it exists.

## Acceptance gate

Build 011.10 may be marked implementation-ready only when:
- [ ] A single canonical migration lineage is selected and its dependencies are complete.
- [ ] The selected identity schema matches every route, RPC, POS, catalog and employee authorization consumer.
- [ ] The actual target Supabase migration history/schema is inspected and reconciled.
- [ ] Customer and employee authentication share one verified person identity.
- [ ] Employee and customer relationships remain independently controlled.
- [ ] All protected employee actions use server-side permission checks, not only active-employee membership.
- [ ] Provider logout/session revocation, CSRF/origin protections and abuse controls are verified.
- [ ] RLS and grants prevent browser access to private identity data.
- [ ] Tests pass for both positive and negative authorization cases.
- [ ] Preview deployment and regression tests pass without changing production.

## Current disposition

This audit corrects the earlier repository-scope finding and prevents duplicate implementation. It does not merge prior branches, run SQL, configure Supabase, change production, or claim that sign-in is live. The next action is a migration-by-migration reconciliation and test review of the existing Build 004 / Build 010.83–010.84 implementation against the Build 011 purchasing/POS branch.
