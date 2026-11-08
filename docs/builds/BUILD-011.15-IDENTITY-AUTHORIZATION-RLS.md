# Build 011.15 — Identity Authorization & Read-Only RLS

Status: **read-only identity RLS applied and catalog-verified in the connected MME Supabase project**.
Branch: `implementation/build-011-15-identity-rls`.
Target Supabase project: `cyatezcfjvewdnibthox`.
Date: 2026-11-08.

## Scope

This build adds least-privilege SELECT access for authenticated users against the installed early identity-matrix schema. It does not introduce the incompatible person/login bridge. It does not create customer or employee accounts, expose identity audit events, or permit client-side writes.

## Applied migration

Supabase migration:
- Version: `20261108142105`
- Name: `build_01115_identity_readonly_rls`
- Source file: `supabase/migrations/20261108000200_build01115_identity_readonly_rls.sql`

The migration:
- Grants SELECT only to the authenticated database role on nine identity/relationship/role tables.
- Creates nine SELECT policies.
- Does not grant anon access.
- Does not grant INSERT, UPDATE or DELETE.
- Does not create a policy on `mme_identity_audit_events`; the audit table remains private to trusted server-side operations.
- Does not alter existing tables, columns, constraints or user data.

## Policy behavior

| Table | Authenticated read boundary |
|---|---|
| `mme_person_identities` | Only the row whose `auth_user_id = auth.uid()` |
| `mme_customer_relationships` | Own active customer relationship and active person identity |
| `mme_employee_relationships` | Own active employee relationship and active person identity |
| `mme_role_assignments` | Own currently effective active employee role assignments |
| `mme_roles` | Active role definitions assigned to the current employee |
| `mme_permission_grants` | Active grants belonging to the user's current active role assignment |
| `mme_integration_entitlements` | Own active employee integration entitlements |
| `mme_profile_appearance_preferences` | Own employee appearance preferences |
| `mme_role_color_registry` | Color definitions for currently assigned active roles |
| `mme_identity_audit_events` | No client access; no policy |

Person identity security lock status is checked by all relationship/employee access paths. Employee status must be active; role assignments must be active and within their effective date window.

## Verification

After migration application, catalog inspection confirmed:
- All nine intended SELECT policies exist and target only `authenticated`.
- The authenticated role has SELECT on exactly the nine intended tables.
- No `anon` table grants were found among the inspected `mme_*` tables.
- No write policies were created.
- The Supabase migration list records version `20261108142105`.

Security advisor result:
- The prior ten RLS-enabled/no-policy findings were reduced to one.
- The sole remaining finding is `mme_identity_audit_events`, intentionally private with no client policy.
- Remediation reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

Performance advisor reports unused indexes on the identity tables. These tables have zero records and no user workload in this project at audit time; the findings are informational and do not justify dropping foreign-key indexes preemptively.

## Test limitations and release gates

The target database had zero Auth users and zero identity/customer/employee rows during preflight. Therefore, this build verifies policy definitions and grants but cannot yet prove real two-user isolation with live identities.

Required staging/integration tests before sign-in release:
1. User A can read only User A's person and customer relationship.
2. User A cannot read User B's person/customer relationship.
3. Employee can read only their own active employee relationship and current role assignments.
4. Terminated/suspended/frozen employee relationship is not visible through the employee self-read policy.
5. Locked person identity cannot read customer or employee relationship data.
6. Expired/revoked role assignment does not expose roles or permission grants.
7. User cannot insert, update, or delete any identity/role record through the public client.
8. Anonymous user cannot read any of the nine tables.
9. Neither customer nor employee can read identity audit events.
10. Employee termination does not change the separate customer relationship state.

Do not claim customer/employee sign-in is production-ready until the application routes, session management, rate limiting, CSRF/origin checks, permission-enforcement service and the tests above pass.

## Disposition

The read-only RLS migration is applied and catalog-verified. The audit table remains intentionally inaccessible to client roles. No Vercel deployment was made. No customer or employee records were created or modified.
