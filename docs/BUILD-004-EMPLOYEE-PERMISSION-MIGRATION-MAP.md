# Build 004 Employee Permission Migration Map

**Branch:** `integration/build004-identity-validation`  
**Purpose:** define a safe compatibility path from the existing Build 001/006 employee authorization system to the Build 004 identity matrix.

## Existing authorization model observed

The integration branch currently contains:
- `employee_relationships` keyed by `auth.users.id`, with active/suspended/terminated employment status.
- `employee_permission_grants` with direct permission keys, JSON scope, grantor, expiry, and revocation fields.
- `employee_security_settings` with the provisioned CEO user ID and global employee-access freeze.
- Separate server-only authorization functions for catalog, inventory inspection, and task actions.
- Existing employee authorization tests and workflow/inspection RPCs that call the legacy permission keys.

Build 004 adds:
- `mme_person_identities` keyed to Auth users.
- `mme_employee_relationships` keyed to person identity.
- `mme_roles`, `mme_role_assignments`, and `mme_permission_grants`.
- Person-level whole-login security lock.
- The server-only `mme_authorize_employee_action` decision function.

These are two distinct authorization stores today. They must not be treated as synchronized.

## Permission key crosswalk proposal

This is a proposed mapping for review, not an automatic grant migration.

| Existing permission | Proposed Build 004 resource | Proposed action |
|---|---|---|
| `inventory.inspection.view` | `inventory.inspection` | `view` |
| `inventory.inspection.submit` | `inventory.inspection` | `submit` |
| `inventory.inspection.resolve` | `inventory.inspection` | `resolve` |
| `inventory.inspection.approve` | `inventory.inspection` | `approve` |
| `catalog.approve` | `catalog` | `approve` |
| `catalog.publish` | `catalog` | `publish` |
| `tasks.<action>` | `tasks` | existing action suffix |

Do not bulk-copy permissions until the target role taxonomy, role assignment authority, grant scope semantics, and approval process are approved.

## Scope compatibility requirements

Legacy scope rules are not uniform:
- Inventory inspection authorization accepts global `{}`, product ID, or location ID scopes.
- Catalog authorization accepts global `{}` or product ID scope.
- Task authorization allows only global, department, department+location, or location-only scopes and explicitly rejects unknown keys.

The Build 004 authorization parity migration adds a server-only scope evaluator for the mapped legacy resources. It preserves inventory product-OR-location matching, catalog product scope, task department/location combinations, and global `{}` scopes while retaining strict JSON containment for unmapped resources. The helper rejects malformed UUIDs and unknown task scope keys. This evaluator is still subject to CI validation and route-level trusted-scope derivation.

**Still required before permission migration:**
1. Define per-resource allowed scope keys and value types.
2. Normalize trusted scope values (especially UUIDs and departments).
3. Preserve the exact legacy OR semantics where intended, or deliberately tighten them with an approved access-change record.
4. Reject unknown keys and malformed values.
5. Derive target product/location/department from trusted database rows, not client request bodies.
6. Add positive and negative equivalence tests comparing legacy and Build 004 decisions for every mapped case.

## CEO and freeze semantics

Legacy authorization requires:
- A non-null CEO provisioned in `employee_security_settings`.
- Global employee access not frozen.
- Active employee relationship.
- Explicit CEO bypass or a valid direct permission grant.

The Build 004 authorization engine now has an additive integration-branch migration that checks the legacy singleton CEO provisioning and global employee-access freeze before every decision. It preserves CEO bypass only for the legacy inventory-inspection, catalog, and task permission families, and only when the provisioned CEO has active legacy and Build 004 employee relationships plus an active/unlocked person identity. New resource families (including CRM) still require explicit Build 004 grants. This parity migration is awaiting fresh-database CI validation. A CEO must never receive authority from a client claim, role label, or email address.

**Still required:** approve who may provision/revoke the legacy CEO singleton and how that control is administered operationally. Preserve the separate person-level whole-login lock. Validate that every protected route uses the centralized decision and that no route bypasses the global freeze.

## Identity linkage and lifecycle

Before any legacy employee is linked to Build 004:
- Verify the Auth user maps to exactly one Build 004 person identity.
- Create or reconcile exactly one employee relationship.
- Do not infer identity from email, phone, caller ID, display name, or user-supplied employee ID.
- Treat duplicate/missing mappings as manual-review cases.
- Keep customer relationship status independent from employee status.
- Ensure termination/suspension/revocation is atomic across both models during a transitional period, with an audit record.

## Required rollout sequence

1. Approve the role taxonomy and this permission/scope crosswalk.
2. Implement an explicit identity-linkage/reconciliation report (read-only first).
3. Add dry-run permission migration that reports every proposed role assignment and grant without writing.
4. Compare old and new authorization decisions across a representative fixture set.
5. Resolve every mismatch and document any intentionally changed access.
6. Migrate grants transactionally with source grant IDs and audit linkage.
7. Keep dual-check mode: require both legacy and Build 004 decisions to allow until cutover is approved.
8. Integrate one protected API route at a time, beginning with inventory inspection.
9. Retire legacy decision functions only after complete route/job/export/webhook coverage and rollback testing.

## Explicit non-goals

- No automatic CEO assignment.
- No wildcard permission expansion.
- No scope broadening.
- No customer account lock on employee termination.
- No production role or permission changes.
- No Build 007 CRM foreign-key rollout yet.

## Current decision

**Migration blocked pending approval of role taxonomy, scope semantics, CEO/freeze parity, and identity linkage.** Keep existing legacy authorization enforcement in place. Do not wire routes to the new Build 004 helper until a reviewed compatibility implementation can preserve or deliberately tighten existing access.
