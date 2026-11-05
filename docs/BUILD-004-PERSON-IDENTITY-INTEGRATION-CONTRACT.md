# Build 004 — Person Identity Integration Contract for Build 001 / Build 008

**Status:** Architecture decision record; additive implementation contract, not a deployed schema  
**Target branch:** `work/build008-build001-catalog-routes`  
**Authority:** `docs/BUILD-004-IDENTITY-MATRIX.md`  
**Scope:** Identity boundary used by catalog, inventory, inspection, and employee authorization

## 1. Decision

Adopt a stable MME `person_id` as the cross-module person key. Keep the authentication provider subject as a separate login credential reference. Employee and customer records remain separate relationship records linked to the same person.

Do not use email, employee number, Supabase Auth UUID, role, title, or profile color as the canonical person key.

This is an additive bridge. It does not replace Supabase Auth or silently relink accounts. Existing auth subjects must be mapped to a person only through a verified, audited migration process.

## 2. Canonical relationship model

| Concept | Canonical key | Purpose |
|---|---|---|
| Person identity | `person_id` (opaque UUID) | Stable MME identity across modules |
| Login identity | `login_identity_id` | One provider subject mapped to one person |
| Provider subject | `provider_key + provider_subject` | Authentication identity; never treated as the person ID |
| Employee relationship | `employee_relationship_id` / `person_id` | Employment facts and employee lifecycle |
| Customer relationship | `customer_relationship_id` / `person_id` | Customer account status and permissions |
| Role assignment | Stable assignment ID + `person_id` | Time-bound role, scope, approver and status |
| Permission grant | Stable grant ID + `person_id` | Action/resource/scope authorization |
| Session | Provider/session ID | Authentication lifecycle; independently revocable |
| Audit event | Stable event ID + actor/target `person_id` | Attributable, append-only governance evidence |

A person may have both an employee and customer relationship. Terminating or suspending the employee relationship must not change the customer relationship. A customer restriction must not change employment. A whole-login security lock is a separate action and must be recorded as such.

## 3. Provider mapping and account linking

The initial compatibility provider key may be `supabase`, but the mapping is an adapter label, not a commitment that Supabase must remain the permanent identity provider.

Required invariants:
- A provider subject maps to at most one person.
- A person may have multiple verified login identities only through an approved account-link flow.
- Email is an attribute to verify and reconcile, never a primary or automatic linking key.
- Provider subject changes, email changes, account recovery and account merges require proof of control, conflict checks, explicit approval where high-risk, and audit events.
- No employee may create, claim, or link another person's identity.
- Unmapped, duplicate, conflicting, disabled or unverified subjects fail closed for employee/inventory access.
- Service identities are separate non-human principals and never impersonate a person.

## 4. Additive database migration shape

The implementation migration must be forward-only and additive in its first phase. It must:
1. Create a private `mme_person_identities` table with opaque UUID primary key, lifecycle state, timestamps and restricted access.
2. Create a private `mme_login_identities` table with opaque ID, person FK, provider key, provider subject, optional Auth-user FK for the current adapter, verification/link status and audit timestamps. Enforce unique provider-subject mapping.
3. Add `person_id` to existing employee relationship records and backfill through an explicit one-to-one mapping from each existing Auth subject. Do not infer identity by email or name.
4. Add person references to permission grants, CEO governance settings, and access audit events; preserve the original Auth-subject columns during the compatibility window.
5. Add constraints only after duplicate, null, orphan and mapping-conflict preflight queries pass.
6. Preserve historical actor and approver attribution. Unresolvable historical rows are quarantined for manual review, not assigned to a guessed person.
7. Keep customer relationship data independent. If no customer relationship table exists, do not fabricate or infer customer accounts as part of this migration.
8. Enable RLS and force RLS on identity/link tables; revoke browser-role access; grant only narrowly scoped server-side functions.
9. Add a reversible operational plan: backup, preflight report, migration, parity checks, dual-read observation, cutover approval, and a documented forward-repair/rollback strategy. Do not drop legacy columns during this phase.

## 5. Authorization contract

After the compatibility bridge:
- Server code validates the current session and resolves its provider subject to exactly one active `person_id`.
- Authorization decisions accept `person_id` as the actor key, not a caller-supplied email or raw provider subject.
- Employee authorization additionally requires an active employee relationship. Customer access checks only the customer relationship. A shared person identity does not make these scopes interchangeable.
- CEO privilege is an explicit, audited person-level assignment; it must not be inferred from email, employee number, title, or client claims.
- Every permission grant is person-keyed, action/resource/scope constrained, effective-dated, revocable, and auditable.
- Inventory and inspection functions must use the same canonical person authorization service; no parallel legacy bypass.
- Any legacy Auth-UUID RPC remains a temporary server-only adapter. It must resolve the UUID through the verified login mapping, call the person-keyed decision point, and be deprecated only after all call sites are migrated.
- No RPC accepts an arbitrary actor identity from an untrusted browser. Caller context must be derived from a validated server session or trusted service identity.

## 6. Migration parity and negative tests

Required database/route tests:
1. Existing employee Auth subjects receive exactly one person mapping and one employee relationship link.
2. Duplicate provider subjects, duplicate person links, orphan Auth subjects, and conflicting account links fail migration preflight.
3. Same person may hold employee and customer relationships; termination changes only employee state.
4. Customer freeze changes only customer state; whole-login lock is explicit and independently audited.
5. Unmapped, unverified, disabled, revoked, or ambiguous login subject is denied.
6. A person without an active employee relationship cannot invoke employee/catalog/inventory/inspection permissions.
7. Person A cannot use Person B's employee grants, CEO assignment, or approval authority.
8. Legacy Auth-UUID adapter resolves only a verified mapping and produces the same decision as the person-keyed authorization function.
9. Grant revocation and session invalidation take effect within the defined revocation target.
10. Audit rows preserve actor, target, approver and original historical attribution; browser roles cannot read or mutate identity mapping tables.
11. Email change does not create a new person or automatically link two people.
12. Service identities cannot acquire person or CEO privileges.

## 7. Current code findings and disposition

The currently imported Build 001 employee access migration uses `employee_relationships.user_id` as both primary key and FK to `auth.users(id)`. Permission grants, CEO settings and audit actor/target references also use Auth UUIDs. The catalog and inventory authorization functions accept an Auth UUID actor. This is a legacy compatibility model and does not satisfy the canonical Build 004 person identity boundary by itself.

**Do not merge or deploy the employee authorization migrations as the final identity implementation.** The current branch is retained for isolated integration work. The identity bridge described here is not yet implemented, and no data migration has been run.

## 8. Decisions still requiring owner approval

- Confirm current provider adapter and exact authoritative subject claim.
- Confirm account-linking and recovery proofing policy.
- Confirm employee/customer relationship source systems and migration ownership.
- Confirm person/login freeze semantics and revocation time objective.
- Confirm CEO identity provisioning and dual-control requirements.
- Confirm staging snapshot, existing migration history and rollback/forward-repair owner.

## 9. Release gates

| Gate | Status |
|---|---|
| Build 004 conceptual model reviewed | Documented |
| Canonical `person_id` selected as cross-module key | Documented |
| Provider subject kept separate | Documented |
| Additive migration design | Documented, not implemented |
| Existing identities backfilled | Not run |
| Person-keyed catalog/inventory authorization | Not implemented |
| Employee/customer independence tested in database | Not run |
| Staging upgrade rehearsal | Blocked pending sanitized schema/history |
| Production merge/deployment | Not performed |
