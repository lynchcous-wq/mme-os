# Build 004 ↔ Build 001 Employee Permission Mapping

**Status:** Mapping analysis only — no legacy grants are copied, transformed, or revoked by this document.  
**Branch:** `integration/build004-identity-validation`

## Why this mapping is required

The existing Build 001/006 employee authorization model is not the same schema as the new Build 004 identity matrix. The legacy model uses:
- `public.employee_relationships` keyed by `auth.users.id`;
- `public.employee_permission_grants` with direct permission keys, JSON scope, expiry and revocation;
- `public.employee_security_settings` for the provisioned CEO identity and global employee-access freeze;
- operation-specific authorization functions.

Build 004 uses:
- `mme_person_identities` linked to Auth users;
- `mme_employee_relationships` linked to person identity;
- `mme_roles`, `mme_role_assignments`, and `mme_permission_grants`;
- `security_status` on person identity;
- centralized `mme_authorize_employee_action`.

These systems must not be treated as interchangeable.

## Candidate operation mapping

| Existing permission key | Build 004 resource | Build 004 action | Notes |
|---|---|---|---|
| `inventory.inspection.view` | `inventory` | `inspection.view` | Read-only inspection access |
| `inventory.inspection.submit` | `inventory` | `inspection.submit` | Submit an inspection |
| `inventory.inspection.resolve` | `inventory` | `inspection.resolve` | Resolve inspection issue |
| `inventory.inspection.approve` | `inventory` | `inspection.approve` | Approval; enforce separation of duties |
| `catalog.*` | `catalog` | suffix after `catalog.` | Each key requires explicit operation-level review |
| `tasks.*` | `tasks` | suffix after `tasks.` | Department/location scope semantics must be preserved |

This table is a proposed naming translation, not an automatic grant conversion. Every resource/action pair must be checked against the actual route and SQL RPC behavior before enabling it.

## Scope mapping — not yet lossless

Legacy inspection authorization accepts either:
- global `{}`;
- a matching `product_id`;
- a matching `location_id`.

The current Build 004 authorization function requires both the role-assignment scope and permission-grant scope to contain the complete requested JSON object. A safe migration needs a canonical scope vocabulary and explicit resource-specific validation. A legacy `location_id` must not be copied as `store_id` unless the IDs are proven to refer to the same entity. Product scope and location scope cannot be silently collapsed.

Build 006 task scopes additionally permit a constrained combination of `department` and `location_id`, and explicitly reject unknown keys. The Build 004 scope function currently checks JSON containment and object type, but does not reject unknown keys or validate resource-specific scope schemas. This is a pre-route-integration blocker.

## CEO and global freeze semantic gap

Legacy authorization fails closed if:
- the singleton `employee_security_settings` row is missing;
- `ceo_user_id` is null;
- `employee_access_frozen` is true;
- the actor does not have an active legacy employee relationship.

When configured, the CEO receives special authorization behavior from the legacy function. Build 004's centralized function currently checks person security status, employee relationship, active role, assignment, and grant, but does not read the legacy CEO provision or global freeze record.

Do not assume a CEO role assignment is equivalent until the CEO bootstrap process, global freeze behavior, emergency lock semantics, and audit path have been explicitly migrated and tested. A missing CEO provision or global freeze must remain fail-closed during transition.

## Required migration sequence

1. Inventory every legacy permission key, route, RPC, background job, and scope dimension.
2. Approve a canonical resource/action/scope registry; reject unknown keys and scope dimensions.
3. Resolve identity crosswalks by matching legacy `auth.users.id` to Build 004 `mme_person_identities.auth_user_id` and active employee relationships. Never use email or caller ID as a key.
4. Design a dry-run conversion report with counts for unmapped identities, duplicate grants, expired/revoked grants, invalid scopes, and CEO/freeze state.
5. Compare effective authorization decisions from both systems over representative positive and negative cases.
6. Obtain explicit approval for CEO/global-freeze migration and the cutover/rollback plan.
7. Only then migrate grants into role assignments and permission grants; preserve original grant provenance and audit actor.
8. Keep legacy authorization as the enforced path until parity and rollback tests pass. Do not dual-authorize with an OR condition.
9. Switch one route at a time, fail closed on errors, and verify route-level tests before expanding.

## Current decision

**Do not wire Build 004 authorization into employee routes yet.** The schema, scope, CEO, and global-freeze differences must be resolved first. No legacy grants have been changed. No user access, production roles, or authentication settings have been modified.
