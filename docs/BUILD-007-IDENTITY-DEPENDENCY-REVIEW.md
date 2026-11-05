# Build 007 — Build 004 Identity Dependency Review

**Build:** 007 — Enterprise CRM  
**Dependency:** Build 004 — Identity Matrix  
**Reviewed branch:** `implementation/build-004-supabase-identity-foundation`  
**Reviewed commit:** `06bb10be174491ee9271555cb7b58d874dfd21c4`  
**Build 004 PR:** #3 (Draft, open, unmerged)  
**CRM implementation branch:** `implementation/build-007-crm-foundation`  
**Review status:** Contract reviewed; integration gate remains open

## 1. Decision

Build 007 will use Build 004's opaque person identity as its identity anchor and will not create parallel customer-account, employee, role, or login identity tables.

The reviewed Build 004 schema is a suitable architectural direction for the CRM dependency: one Auth subject maps to one opaque MME person identity, while customer and employee relationships are separate records. A person may hold both relationships independently.

**Do not yet add CRM foreign keys or apply CRM migrations against this contract.** Build 004 PR #3 is still Draft and unmerged, and its migrations are not present in the Build 001/006 integration candidate on which this Build 007 branch is based. Integrate the reviewed dependency through the normal reviewed migration path before creating CRM tables that reference it.

## 2. Verified contract

The reviewed migration set defines:

- `mme_person_identities`: one-to-one link from Supabase `auth.users.id` to an opaque MME person identity.
- `mme_customer_relationships`: independent customer lifecycle linked to a person identity.
- `mme_employee_relationships`: independent employee lifecycle linked to a person identity.
- `mme_roles`, `mme_role_assignments`, and `mme_permission_grants`: employee role and permission model with explicit resource/action/scope.
- `mme_integration_entitlements`: scoped employee integration grants.
- `mme_identity_audit_events`: identity audit records.
- `mme_profile_appearance_preferences` and `mme_role_color_registry`: presentation preferences only; never authorization.
- Auth-user insert trigger creates an opaque person identity only; it does not automatically create customer or employee relationships.
- A separate whole-login security lock is independent of customer/employee lifecycle.
- Direct client table access is intentionally closed: RLS is enabled and `anon`/`authenticated` receive no table privileges in the foundation migration.
- Identity audit mutation is rejected by database triggers; this is defense-in-depth, not protection from database owners or schema administrators.

## 3. Required Build 007 behavior

- CRM customer profiles reference `mme_customer_relationships.id` and/or `mme_person_identities.id` according to the approved data minimization decision. Do not copy Auth email or duplicate identity PII into CRM tables unless a documented CRM-owned contact field is necessary.
- Lead records may exist before identity verification. Anonymous and unverified inquiries must not be silently linked to an existing person.
- Customer record matching uses verified identifiers and reviewable evidence. Ambiguous matches enter manual duplicate review; they never disclose an existing profile or auto-merge.
- CRM representative ownership and assignment records reference the authoritative employee relationship, not a user-supplied employee ID or profile attribute.
- Authorization is evaluated server-side using active employee relationship, active role assignment, permission grant, scope, effective time and whole-login security state. Client navigation, appearance, department text and caller ID are never grants.
- Employee termination or suspension does not alter the person's customer relationship. Whole-login lock is a distinct security action.
- All privileged identity/CRM linkage, merge, assignment, export and consent changes require actor, reason, before/after evidence and append-only audit linkage.

## 4. Integration and test gaps found

The inspected Build 004 branch contains six migrations and an implementation decision document. The inspected tree did not contain dedicated pgTAP identity test files. The branch's reported GitHub commit status showed a successful Vercel deployment status, but this is not evidence that the migrations were applied to a disposable Supabase database or that RLS, grants, triggers and lifecycle rules passed database tests.

Before Build 007 references this contract, add or verify database tests for:

1. Auth user insert creates exactly one person identity; repeated invocation is duplicate-safe.
2. Customer and employee relationships can coexist for one person.
3. Customer suspension/freeze does not change employee status; employee termination does not change customer status.
4. Anon and authenticated roles cannot select or mutate protected identity tables directly.
5. Runtime server role has only the intended privileges; no application role owns protected tables or can bypass RLS.
6. Identity audit UPDATE, DELETE and TRUNCATE are rejected for runtime roles; privileged DDL ownership is separately controlled.
7. Locked identities are denied on every protected server route; the schema check alone is not treated as enforcement.
8. Role assignments with invalid effective windows, expired/revoked grants or mismatched scopes are denied.
9. Client-controlled metadata, appearance settings and caller ID cannot grant or escalate permissions.
10. Employee relationship termination and role/entitlement revocation are atomic and audited.
11. No service-role/secret key appears in browser bundles, Git history, workflow output or public environment variables.

The reviewed migration schema also does not itself implement server-side authorization middleware, session revocation, customer/employee lifecycle services, MFA, or the UX flows described in its implementation document. Those remain implementation work and must not be inferred from the table definitions.

## 5. Schema questions to resolve with Build 004 owner

- Define the canonical server-side permission evaluation function/API and its failure behavior before CRM routes are written.
- Define whether CRM's customer foreign key targets `mme_customer_relationships.id`, person identity, or both for each use case. Prefer the customer relationship as the customer lifecycle boundary.
- Define effective-time and uniqueness constraints for role assignments and permission grants; validate `effective_until > effective_from` when present.
- Define the transactional lifecycle procedure for employee termination, role revocation and entitlement revocation.
- Define whole-login lock enforcement and session revocation orchestration.
- Define a tested migration ordering and rollback/recovery plan for integrating Build 004 with the Build 001/006 candidate.
- Add repeatable database tests and confirm the exact Supabase/PostgreSQL trigger privilege behavior described in the Build 004 document.

## 6. Build 007 implementation gate

- [x] Reviewed Build 004 migrations and implementation decision document.
- [x] Confirmed person identity and customer/employee lifecycle separation.
- [x] Confirmed closed direct-client table boundary and intended server-side authorization model.
- [x] Confirmed Build 004 PR #3 is Draft and unmerged.
- [ ] Integrate Build 004 migration chain into the approved Build 001/006 base.
- [ ] Add and pass Build 004 database/RLS/authorization tests.
- [ ] Verify deployed identity provider and production/staging configuration with approved access.
- [ ] Obtain approval for the canonical permission-evaluation and lifecycle service contracts.
- [ ] Only then add Build 007 CRM migrations with foreign keys to the approved identity contract.

**Outcome:** Identity architecture reviewed and CRM integration requirements clarified. Build 007 remains in discovery/dependency reconciliation. No CRM schema, API, UI, telephony, messaging or production integration is claimed as implemented.
