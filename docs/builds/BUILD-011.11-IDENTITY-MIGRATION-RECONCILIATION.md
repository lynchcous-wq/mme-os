# Build 011.11 — Identity Migration Reconciliation

Status: **migration lineage conflict identified and documented; no migration selected or applied**.
Branch: `implementation/build-011-11-identity-migration-reconciliation`.
Base: `implementation/build-011-10-authentication-consolidation`.
Date: 2026-11-08.

## Executive decision

Do not cherry-pick or apply the early Build 004 identity-matrix foundation migration from `integration/build004-identity-validation` together with the later person/login bridge migration from `implementation/build-010-84-identity-review-dashboard`. They define incompatible versions of the same core table names.

The correct path is to preserve the later canonical person/login identity model and reconcile its full dependency chain with the Build 011 codebase and the target Supabase migration history. This decision is based on source compatibility and the existing Build 010 customer-link workflow; it is not evidence that this migration lineage has been applied to production.

## 1. Migration lineage comparison

### Lineage A — early identity matrix branch

Branch: `integration/build004-identity-validation`.

Key migrations:
- `20261103000100_identity_matrix_foundation.sql`
- `20261103000200_auth_identity_trigger.sql`
- `20261103000300_identity_audit_append_only.sql`
- `20261103000400_identity_security_lock.sql`
- `20261103000500_auth_trigger_execute_lock.sql`
- `20261103000601_identity_authorization_engine.sql`

Its `mme_person_identities` table uses `id` as the primary key and stores `auth_user_id` directly on the person row. It also creates a separate role/permission model with `mme_roles`, `mme_role_assignments`, `mme_permission_grants`, and a customer/employee relationship model keyed to that identity ID.

The associated authorization engine uses the early role-assignment/grant model and expects a person security status column. This is a distinct schema lineage, not a compatible additive predecessor to the later bridge as currently authored.

### Lineage B — person/login identity bridge

Branch: `implementation/build-010-84-identity-review-dashboard`.

Key migrations:
- `20261103008400_build004_person_login_identity_bridge.sql`
- `20261103008420_build004_identity_privilege_hardening.sql`
- `20261103008430_build004_person_keyed_authorization.sql`
- `20261103008440_build004_require_active_person_identity.sql`
- `20261106004000_build010_customer_identity_link_requests.sql`
- `20261106005000_build010_customer_identity_review_dashboard.sql`

Its `mme_person_identities` table uses `person_id` as the primary key and stores lifecycle status. Provider login mappings are separated into `mme_login_identities`, including provider, subject, verification and revocation state. It adds nullable `person_id` references to pre-existing employee relationships and permission grants. Its customer-linking workflow provisions a verified login mapping and customer account link only after staff review.

The later Build 010 customer-link workflow depends on the person/login bridge and other pre-existing customer portal and employee-security schema. It must not be separated from those prerequisites.

## 2. Hard incompatibilities and migration hazards

1. **Same table, different primary key:** Lineage A creates `mme_person_identities(id, auth_user_id, created_at)`; Lineage B creates `mme_person_identities(person_id, lifecycle_status, merged_into_person_id, ...)`. Both use `CREATE TABLE` rather than an idempotent compatible extension. Applying both in sequence will fail or leave the wrong contract depending on order.
2. **Different login authority:** Lineage A binds Auth user ID directly to the person row and installs an Auth trigger. Lineage B separates person and login identities and explicitly requires a verified mapping. Do not enable both identity creation/linking authorities.
3. **Different relationship/authorization models:** Lineage A creates `mme_employee_relationships`, `mme_roles`, `mme_role_assignments`, and `mme_permission_grants`. Lineage B extends legacy `employee_relationships` and `employee_permission_grants` with person keys. The route helper and SQL RPCs must target one selected authority.
4. **Legacy schema prerequisites:** The person/login bridge alters `employee_relationships`, `employee_permission_grants`, `employee_security_settings`, `employee_access_audit_events`, and `products`. The full base definitions and their migrations must be present before the bridge is applied.
5. **RPC contract drift:** The application helper calls `mme_resolve_person_for_auth_subject` and expects a UUID result. This function exists in Lineage B. The early matrix branch's trigger does not provide the same verified login mapping contract.
6. **Customer account linking dependencies:** Build 010.83/010.84 expects `mme_customer_account_links`, `mme_customer_portal_provision_account_link`, the person/login bridge and active employee review authorization. Those dependencies must be traced to exact migration files and migration order.
7. **Duplicate migration version:** The Build 010.84 branch contains two different migration files with version prefix `20261106004000`: customer identity link requests and employee lifecycle HR administration. Supabase migration version identifiers must be unique; resolve this collision before using the migration set.
8. **Migration timestamp order:** The person/login bridge migrations carry 2026-11-03 timestamps while Build 010 customer-link and governance migrations carry 2026-11-06 timestamps. The selected target migration history must be checked for already-applied versions and gaps before any replay or reordering.
9. **Authorization enforcement parity:** The employee helper in `lib/auth/supabase-session.ts` verifies active employee membership via `employee_relationships`; it does not call the person-keyed action/resource authorization RPC. Protected endpoints need permission-level authorization.
10. **Governance ledger limitation:** The privileged-access governance migration explicitly records request/review/freeze ledgers; it states that ledger records do not themselves change live role claims or enforce provider sessions. Do not describe it as active session revocation or live account freeze enforcement.

## 3. Duplicate timestamp finding

The Build 010.84 migration tree contains:
- `20261106004000_build010_customer_identity_link_requests.sql`
- `20261106004000_build010_employee_lifecycle_hr_administration.sql`

They share a migration version. Before any deployment, rename one migration to an unused, later version while preserving the chronological dependency order, then update references and migration tests. Do not silently rename an already-applied production migration; first inspect the actual migration ledger.

## 4. Recommended target contract

Use the **person/login identity bridge** as the canonical target design because it supports:
- One MME person across one or more explicitly verified provider login identities.
- Independent lifecycle state for the person and employee/customer relationships.
- No email-only auto-linking.
- Audited and revocable provider identity mappings.
- Compatibility with the existing Build 010 customer identity review flow.

This is a design selection for consolidation, not approval to run the migration. Preserve all existing employee/customer tables and authorization behavior through additive compatibility changes. Do not import Lineage A's same-named person, role or relationship tables into the selected branch.

## 5. Required preflight before writing or applying a migration

- Obtain the exact active target Supabase project/environment and read-only schema access.
- Export the migration ledger versions and compare with every candidate migration filename.
- Inspect actual definitions of all tables/functions referenced by the person/login bridge and Build 010 customer-link workflow.
- Confirm whether the early identity-matrix migrations were ever applied to the target. If so, write a dedicated forward-only compatibility migration; do not attempt to apply the incompatible later `CREATE TABLE`.
- Confirm whether any production Auth users or customer/employee links exist and design a reviewed, reversible mapping/backfill plan. Never infer identity matches from email alone.
- Resolve the duplicate migration timestamp before migration packaging.
- Verify all RLS, grants, security-definer function ownership/search_path, function execute privileges and service-role-only operations.
- Run the complete SQL test suite against a disposable staging database created from the actual baseline.
- Confirm rollback/forward-recovery plan and backups before applying any schema changes.

## 6. Authentication hardening items for the selected app code

- Keep the existing Supabase Auth provider; no second auth vendor.
- Return minimum customer/employee access claims to the browser; avoid returning internal person IDs unless an explicitly documented client contract requires them.
- Use a shared permission authorization service for protected employee operations, deriving the actor from the verified session.
- Make sign-out revoke provider refresh/session credentials where supported, then clear HttpOnly cookies; document any residual access-token validity window.
- Keep access and refresh tokens HttpOnly, Secure in production, SameSite=Lax or stricter where compatible, with bounded lifetimes and rotation.
- Apply a single safe origin/CSRF helper to all cookie-authenticated mutations.
- Apply rate limits to registration, sign-in, recovery, verification and identity-link requests.
- Avoid detailed credential/provider error messages and never log tokens, passwords or recovery material.
- Add integration tests proving employee termination does not disable customer access and customer restriction does not alter employee status.

## 7. Acceptance criteria

- [ ] Canonical person/login schema selected and mapped to the active target's actual migration history.
- [ ] No conflicting duplicate person or role authority is included.
- [ ] All prerequisite employee, customer portal, account-link and permission migrations are present and ordered.
- [ ] Duplicate migration version is resolved without rewriting applied production history.
- [ ] Existing user/link data has an approved non-email-only mapping plan.
- [ ] Auth route contracts match the selected schema and RPC signatures.
- [ ] Employee routes enforce action/resource/scope permission decisions.
- [ ] Session revocation, CSRF/origin checks, rate limits and data-minimizing responses are tested.
- [ ] RLS, grants, function ownership and security-definer boundaries pass tests.
- [ ] Staging migration and app tests pass against a clean database baseline.
- [ ] Production migration is explicitly approved and separately verified.

## 8. Current disposition

This build commits the migration reconciliation decision and blocking hazards. No SQL migration was copied into the active Build 011 branch, no migration was applied to Supabase, no user identity data was changed, and no Vercel deployment was made.

The next implementation task is to inspect the active Supabase migration ledger and schema through an authorized read-only connection, then prepare one compatibility migration for the actual state found. If read-only project access is not available, stop at a reviewed migration package and request an owner-run schema snapshot; do not guess.
