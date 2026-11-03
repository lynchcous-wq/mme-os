# Build 004 — Supabase implementation decision and foundation

**Decision:** Approved — Supabase Auth + PostgreSQL  
**Status:** Initial database foundation drafted; not yet applied to a Supabase project  
**Repository:** `lynchcous-wq/mme-os`  
**Branch:** `implementation/build-004-supabase-identity-foundation`

## 1. Approved architecture

- Supabase Auth is the authentication provider and source of the immutable authentication subject.
- PostgreSQL stores MME's opaque person identity and distinct customer/employee relationships, roles, scoped grants, integration entitlements, appearance preferences, role-color registry, and audit events.
- MME OS server-side services are the authorization authority. Authentication by Supabase does not itself grant an MME role or permission.
- Email is not the permanent primary key. Supabase Auth verifies and manages login email; MME maps the Auth subject UUID to an opaque person identity.
- One person may have both a customer relationship and an employee relationship under one login. These relationship records have independent lifecycle state.
- The standard MME profile appearance is the default. Appearance and role colors are descriptive only and never authorize access.

## 2. Initial migration

`supabase/migrations/20261103000100_identity_matrix_foundation.sql` creates:

- Person identity linked one-to-one to `auth.users`.
- Independent customer and employee relationship tables.
- Versionable organizational role definitions and role assignments.
- Explicit resource/action/scope permission grants.
- Scoped integration entitlements.
- Optional employee appearance preferences.
- Unique role-color token and value registry.
- Append-only identity audit events.
- An Auth-user insert trigger that creates only the opaque person identity. It deliberately does not create a customer or employee relationship automatically.

All tables have Row Level Security enabled. This first migration creates no browser/client access policies and revokes table access from `anon` and `authenticated`. The initial boundary is intentionally closed: access must be implemented through reviewed server-side services. The Supabase service-role key must never be exposed to browser code, committed to source control, or placed in a `NEXT_PUBLIC_*` variable.

## 3. Lifecycle guarantees

- Employee termination changes the employee relationship and revokes employee role assignments/entitlements through a controlled server workflow; it does not close the customer relationship.
- Customer suspension/freeze changes the customer relationship only.
- A whole-login security lock is a separate identity/session action, not a substitute for termination or customer closure.
- CEO freeze/restore actions require explicit relationship scope, reason, actor, and audit evidence.
- No role, department, title, color, profile setting, or client-rendered navigation grants access.

## 4. Not included / no production claim

This foundation does not yet provide a sign-in page, signup UX, password reset/recovery UX, MFA enrollment, email-change workflow, role administration screens, API authorization middleware, session revocation orchestration, HR provisioning/offboarding integration, or deployed Supabase database. No live authentication or production authorization is claimed.

## 5. Required environment setup

Create a dedicated Supabase project for the intended MME OS environment. Configure project URL and publishable/anon key as server/client configuration only where appropriate. Keep the service-role key server-only in the hosting provider's secret manager. Do not paste secrets into chat, GitHub files, screenshots, or source code.

Before applying the migration:
1. Confirm the correct Supabase project and environment (development/staging first).
2. Review existing Replit and hosting configuration for any existing identity provider or user data; do not replace or migrate existing users without a mapping and rollback plan.
3. Apply the migration in a non-production project and inspect the schema, trigger, RLS state, and grants.
4. Test Auth signup creates one person identity, repeated trigger execution does not duplicate it, and unauthenticated/authenticated browser clients cannot query identity tables directly.
5. Test employee and customer relationships coexist and lifecycle updates remain independent.
6. Review database deletion/retention behavior and the append-only audit policy before production use.

## 6. Next implementation sequence

1. Add Supabase SSR/client libraries and reproducible lockfile after confirming the repository's dependency policy and resolving the existing npm audit findings.
2. Build server-only Supabase client helpers and a verified session boundary.
3. Implement centralized server-side authorization checks with deny-by-default action/resource/scope evaluation; do not use client metadata or user-editable claims as grants.
4. Add relationship lifecycle services and transactional audit writes.
5. Add tests for duplicate identity prevention, cross-relationship isolation, unauthorized reads/writes, role escalation, termination/customer independence, audit immutability, and role-color uniqueness.
6. Add MFA and step-up authentication for CEO and privileged operations.
7. Add UI and HR/employee provisioning only after the server-side policy and test suite are in place.

## 7. Acceptance evidence still required

- Migration applied successfully to a controlled Supabase project.
- RLS and grants verified from anon, authenticated, and server-only contexts.
- Auth subject maps to exactly one MME person identity.
- Customer and employee relationship lifecycle independence proven by tests.
- All protected server operations deny by default and audit privileged changes.
- No service-role secret appears in client bundles, logs, repository history, or public environment variables.
- Build, tests, and dependency audit reviewed and passing with documented exceptions if any.


## 8. Environment variable names

The repository example uses the current Supabase key naming convention:

- `NEXT_PUBLIC_SUPABASE_URL` — project URL.
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` — publishable key; safe for browser use when protected by RLS and server authorization design.
- `SUPABASE_URL` — server-side project URL.
- `SUPABASE_SECRET_KEY` — server-only secret; never use a `NEXT_PUBLIC_` prefix.

Do not add actual credentials to `.env.example`. Set real values only in local ignored environment files or the hosting provider's encrypted secret manager. The secret key must not enter client bundles, logs, source control, or chat.

## 9. Audit immutability hardening

The dependent security branch adds `supabase/migrations/20261103000300_identity_audit_append_only.sql`. It rejects UPDATE and DELETE on audit rows and rejects TRUNCATE through database triggers. It also revokes direct sequence privileges from `public`, `anon`, and `authenticated`.

This is defense-in-depth, not tamper-proof storage against the database owner or a sufficiently privileged administrator who can disable triggers or alter the schema. Production deployment must keep runtime application roles from owning the audit table or having DDL/trigger-management privileges. Verify that the generated identity sequence name matches the deployed schema before applying this migration. Test inserts through the approved server-side path and verify UPDATE, DELETE, and TRUNCATE are rejected for runtime roles.
