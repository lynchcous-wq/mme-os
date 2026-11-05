# Build 004 Permission Migration Dry Run

**Branch:** `integration/build004-identity-validation`  
**Status:** SQL implementation and pgTAP coverage added; CI validation pending.  
**Mode:** Read-only. No grants, roles, assignments, identities, or employee records are created or changed.

## Function

`public.mme_employee_permission_migration_dry_run()`

Service-role only. For each legacy permission grant it returns:
- Source grant ID and legacy Auth user ID.
- Existing Build 004 person and employee relationship IDs, if linked.
- Source permission key and whether the grant is active, revoked, or expired.
- Proposed resource/action mapping for recognized permission keys.
- Original scope, when a known permission mapping exists.
- Classification and explicit review reasons.

## Proposed mappings

- `inventory.inspection.view|submit|resolve|approve` → resource `inventory.inspection`, corresponding action.
- `catalog.approve|publish` → resource `catalog`, corresponding action.
- `tasks.<action>` → resource `tasks`, existing action suffix.

Unknown permission keys are `unsupported`; they are not guessed or wildcard-mapped.

## Scope checks

- Inventory: global `{}`, product-only, or location-only scope.
- Catalog: global `{}` or product-only scope.
- Tasks: global `{}`, department-only, location-only, or department+location. Unknown keys are rejected from candidacy; location IDs must be UUID-shaped.

These are compatibility diagnostics, not permission decisions. The legacy inventory OR-scope and task scope semantics must still be verified against the protected target data and equivalent authorization fixtures.

## Classifications

- `mapping_candidate`: known key, canonical scope, and complete identity linkage.
- `review_required`: identity linkage or scope needs human review.
- `unsupported`: no approved permission-key crosswalk exists.
- `inactive`: source grant is revoked or expired.

No classification automatically authorizes a migration. The dry run now also forces `review_required` when the legacy CEO is unprovisioned or global employee access is frozen. CEO identity linkage, source-grant provenance, role taxonomy, and dual-check rollout remain separate approval gates.

## Validation

The pgTAP test checks service-role-only execution, proposed key mappings, unknown-scope rejection, unsupported keys, complete source-grant visibility, and absence of writes to role assignments and legacy grants. Full fresh-database CI must pass before this dependency is considered validated.
