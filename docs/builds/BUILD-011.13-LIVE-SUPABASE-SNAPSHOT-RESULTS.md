# Build 011.13 — Live Supabase Snapshot Results

Status: **live read-only inspection completed; additive hardening applied and verified under Build 011.14**.
Date: 2026-11-08.
Supabase project ref: `cyatezcfjvewdnibthox`.
Project status: `ACTIVE_HEALTHY`; PostgreSQL 17.

## 1. Verified target state

The connected Supabase project is the MME project returned by the connected account. Read-only inspection confirmed:

- `public.mme_person_identities` exists with primary key `id` and unique `auth_user_id`.
- `public.mme_customer_relationships` and `public.mme_employee_relationships` each reference `mme_person_identities.id`.
- The early identity-matrix role model exists: `mme_roles`, `mme_role_assignments`, `mme_permission_grants`, `mme_integration_entitlements`, `mme_role_color_registry`, and `mme_profile_appearance_preferences`.
- `mme_identity_audit_events` exists and has append-only mutation protection triggers.
- All ten identity/role tables inspected have RLS enabled.
- The identity tables inspected contain zero rows.
- `auth.users` contains zero rows at the time of inspection.
- The `supabase_migrations.schema_migrations` table was not present in the inspected project at the time of the initial check. After applying Build 011.14 via the Supabase migration API, the API reports the new migration version `20261108141731` named `build_01114_identity_security_hardening`.

The live database is therefore using the **early identity-matrix schema**, not the later person/login bridge. Do not apply the later bridge's conflicting `CREATE TABLE public.mme_person_identities` migration set to this project.

## 2. Security findings

Supabase security advisor initially reported:
- Ten identity/role tables with RLS enabled but no policies.
- `public.mme_audit_person_identity_created()` was executable by `PUBLIC` and is SECURITY DEFINER.
- `public.mme_reject_identity_audit_mutation()` had PUBLIC execute privilege; this is a trigger-only function and should not be a public RPC.

The audit found both functions use an empty search path. The audit insertion trigger writes to the append-only identity audit table; the Auth trigger creates the person identity row. Their trigger invocation does not require public API callers to execute the trigger functions directly.

The absence of RLS policies means ordinary anon/authenticated table access is denied by RLS. Keep that deny-by-default state until reviewed policies and server authorization are implemented. Do not add broad policies to silence the advisor.

## 3. Build 011.14 hardening applied

The following additive migration was applied successfully to the connected project:

`20261108141731_build_01114_identity_security_hardening`

Changes:
- Revoked EXECUTE from `PUBLIC`, `anon` and `authenticated` on the trigger-only functions `mme_audit_person_identity_created()` and `mme_reject_identity_audit_mutation()`.
- Added indexes to cover five foreign keys flagged by the Supabase performance advisor:
  - `mme_identity_audit_events.actor_identity_id`
  - `mme_integration_entitlements.employee_relationship_id`
  - `mme_permission_grants.role_assignment_id`
  - `mme_person_identities.security_locked_by_identity_id`
  - `mme_role_assignments.role_id`

Post-apply verification:
- Supabase migration API reports the new migration.
- SQL verification shows only `postgres` retains EXECUTE on both trigger functions.
- SQL verification confirms all five indexes exist.
- No RLS policy was added and no data was inserted, updated or deleted.

The advisor still reports the ten RLS-enabled/no-policy findings. This is expected and intentionally remains a release blocker for client-facing identity features until least-privilege policies and server authorization are implemented and tested. Performance advisor may report the new indexes as unused because the tables are empty and there has been no workload; do not remove them solely on that basis.

## 4. Migration lineage decision

The actual target schema resolves the prior ambiguity: the early Build 004 identity matrix is already present. The later person/login bridge migration lineage is incompatible with this target as written and must not be applied. If a future product requirement calls for separate login-identity mappings, it must be delivered as a forward-only compatibility migration that extends this installed schema, preserves existing keys and relationships, and includes a reviewed migration/backfill plan.

The absence of an initial migration ledger means the source repository's older migration sequence is not represented by the target's recorded migration history. Reconstruct a baseline from the actual database only after reviewing the complete schema, functions, policies, triggers, grants, extensions and Auth configuration. Do not blindly replay old migrations.

## 5. Outstanding blockers

- Design and test least-privilege RLS policies for the ten identity/role tables.
- Review and constrain all service-role and server-side data access.
- Inspect all triggers, constraints, grants and dependent functions beyond the initial identity subset.
- Verify Supabase Auth provider settings and production redirect configuration.
- Build the shared application identity adapter against the installed early schema.
- Verify the current application auth routes and permission checks against this exact database contract.
- Stage and test customer/employee separation, account freeze, session revocation and audit behavior.
- Do not enable public customer/employee sign-in until these controls pass.

## 6. Release disposition

Build 011.13 live inspection is complete. Build 011.14 additive database hardening has been applied and verified. Customer/employee sign-in remains **not production-ready** because RLS policies and application-level authorization are not yet in place. No Vercel deployment was made.
