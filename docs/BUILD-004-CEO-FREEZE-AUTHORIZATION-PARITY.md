# Build 004 CEO and Global Freeze Authorization Parity

**Migration:** `20261104003100_build004_authorization_ceo_freeze_parity.sql`  
**Status:** Added to the integration branch; fresh-database CI pending.

## Behavior

The centralized Build 004 authorization decision now preserves the legacy global employee-access control:
- Missing singleton control row denies.
- Unprovisioned CEO denies.
- Global employee freeze denies all Build 004 employee authorization decisions.

The legacy CEO bypass is narrowly retained for existing permission families only:
- `inventory.inspection`: `view`, `submit`, `resolve`, `approve`
- `catalog`: `approve`, `publish`
- `tasks`: syntactically valid existing task action suffixes

For this bypass, the CEO must be the exact provisioned `ceo_user_id`, have an active legacy employee relationship, an active Build 004 employee relationship, and an active/unlocked Build 004 person identity.

CEO bypass does not extend to new resource families such as CRM. Those continue to require explicit active Build 004 role assignments and permission grants.

## Test coverage

The authorization-engine pgTAP suite now checks:
- Existing active role/grant and scope behavior.
- Whole-login lock, termination, inactive role, expired assignment, malformed input.
- Global employee freeze denies an otherwise authorized employee.
- Global `{}` role assignment and grant scopes authorize across requested scopes, while narrower scopes remain constrained.
- Inventory product/location OR semantics and task department/location scope semantics match legacy rules.
- Catalog approval/publication requires a real product, non-self actor, and the legacy pending-approval state checks.
- A correctly provisioned and active CEO retains the legacy inventory inspection bypass.
- CEO does not receive automatic bypass for a new resource family.

## Safety limits

This does not migrate any permission grants, define the final role taxonomy, or authorize route integration. Existing legacy functions remain in place. Scope translation and old/new decision equivalence still require a dedicated fixture matrix before cutover.
