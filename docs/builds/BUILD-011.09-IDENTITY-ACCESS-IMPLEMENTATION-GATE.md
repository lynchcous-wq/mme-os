# Build 011.09 — Identity & Access Implementation Gate

Status: **source audit complete; production identity implementation blocked pending authoritative schema/provider verification**.
Branch: `implementation/build-011-09-identity-access-foundation`.
Base: `implementation/build-011-08-commerce-identity-cart-checkout`.
Date: 2026-11-08.

## 1. Goal

Implement the MME OS shared identity and role-based access foundation for customer and employee experiences. This build must follow the existing Build 004 Identity Matrix and must not create a second login, person, role, or permission authority.

The intended user experience is one verified login/person identity that can have both a customer relationship and an employee relationship. Customer and employee access, status, sessions, and permissions remain independently controlled.

## 2. Source audit findings on the Build 011.08 branch

Confirmed by repository inspection:

1. `docs/BUILD-004-IDENTITY-MATRIX.md` contains the canonical design: one person identity; separate customer and employee relationships; independent employee offboarding; deny-by-default server-side authorization; integration entitlements; CEO-governed audited controls; and optional role colors that never affect permissions.
2. `lib/pos/authenticated-server.ts` contains a POS-specific Supabase bearer-token verification path. It calls Supabase Auth and then invokes `mme_resolve_person_for_auth_subject` to map the auth subject to a person ID. This is not a complete customer/employee storefront authentication service.
3. The repository tree for the audited branch contains a single migration file, `supabase/migrations/20261105001800_build010_warranty_security_operations_dashboard.sql`. The tree does not expose the canonical identity tables/functions/policies that the POS helper expects.
4. The GitHub code-search pass did not return indexed matches for `mme_person_identities`, `mme_resolve_person_for_auth_subject`, or `role_assignments`. A search-index miss is not proof that those objects do not exist in a live database or another branch.
5. Existing Stripe refund routes are POS-specific and remain untouched. They do not implement customer sign-in or storefront checkout.
6. The branch does not establish the current live Supabase Auth configuration, actual database schema, RLS policies, Vercel environment-variable presence, or production identity-provider configuration.

## 3. Why code changes are gated

Creating identity tables or an auth adapter without verifying the current live schema risks duplicating or conflicting with the previously defined MME identity authority. In particular, the existing POS helper references a database RPC whose definition was not found in the audited branch. Guessing its return shape, table names, relationship keys, or role semantics would be unsafe.

**No production migration, credential flow, new auth provider, or account-linking behavior is introduced in this gate commit.** This is an explicit safety gate, not a claim that identity implementation is complete.

## 4. Required verification before schema or auth code is written

The authorized project owner must verify the following in the connected Supabase project and Vercel project settings. Inspect names, metadata, and policy definitions only; never expose secret values.

### Supabase Auth
- Project URL and environment (development/staging/production).
- Enabled auth providers and email/username sign-in configuration.
- Email verification, password recovery, redirect allowlist, MFA availability, session settings and token lifetime.
- Existing Auth users and their mapping to canonical person identities; do not export credentials or recovery secrets.

### Database authority
- Actual definitions and constraints for person identity, auth-subject mapping, customer relationship, employee relationship, roles, role assignments, permissions/grants, account freeze, identity audit, and session/security events.
- Definition, grants, ownership and behavior of `mme_resolve_person_for_auth_subject` and any related RPCs.
- RLS enabled state, all policies, table grants, function execute grants, service-role-only paths and security-definer functions.
- Whether customer and employee records already link to the same person identity and how independent lifecycle states are represented.
- Whether the prior identity schema is in a different branch, migration history, or externally managed Supabase project.

### Vercel configuration
- Presence (not values) of the required public Supabase URL/anon key and server-only service role key, separately for preview and production.
- Correct environment scoping and redeploy requirements after configuration.
- Confirm no secrets are committed in GitHub or exposed in client bundles.

## 5. Implementation sequence after verification

### 5.1 Canonical identity adapter
- Reuse the verified auth provider and canonical person mapping.
- Resolve the authenticated subject server-side to one opaque person ID.
- Do not accept person ID, role, relationship status, or permissions from browser input as authoritative.
- Use explicit error handling for unlinked, suspended, frozen, or ambiguous identities.
- Do not silently merge duplicate people. Require a verified recovery/linking workflow with audit evidence.

### 5.2 Customer and employee relationship access
- Resolve customer and employee relationship state independently.
- A shared login can access customer and employee surfaces only when each relationship is active and the relevant permission checks pass.
- Terminating/suspending employee access revokes employee grants and sessions according to policy but does not close customer access.
- Customer account restrictions do not alter HR/employment state.
- Whole-login security lock is a separate action from relationship status and requires its own reason, scope and audit event.

### 5.3 Server-side authorization
- Centralize an authorization function taking actor, action, resource, scope and relevant context.
- Deny by default. Enforce on every protected route, server action, API, export, job and database boundary.
- Verify current grants and revocation state; do not trust client navigation visibility or stale role claims.
- Preserve POS-specific authentication behavior while refactoring only through compatibility-tested adapters.
- Keep service-role access server-side and narrow; never return it or privileged tokens to the browser.

### 5.4 Audit and lifecycle
- Append-only events for identity linking, relationship activation/deactivation, role/grant changes, account freeze/restore, session revocation, login/security events, and privileged access.
- Include actor/service, target person/relationship, event type, timestamp, correlation ID, outcome, reason/approval reference and schema/policy version.
- Never log passwords, bearer tokens, recovery codes or unnecessary personal data.
- Require step-up/MFA for CEO/admin and privileged actions when supported by the configured provider.

## 6. Required test evidence

- One person can hold both customer and employee relationships without duplicate login identity.
- Customer-only login cannot invoke employee endpoints or read employee data.
- Employee-only login cannot access customer data without an active customer relationship and applicable permission.
- Employee termination revokes employee access but leaves customer access unchanged.
- Customer suspension/freeze leaves employment state unchanged.
- Frozen/terminated/revoked sessions are denied on server routes and database access.
- Cross-person profile, order, cart and employee-record access is denied.
- Browser-supplied person ID, role, status, or permission cannot escalate access.
- Unknown/unlinked auth subject fails closed without creating an accidental person.
- Identity resolution RPC is tested for valid, invalid, ambiguous and inactive identities.
- RLS policies and direct database access are tested independently of the UI.
- Audit events are emitted for privileged actions and contain no secrets.
- POS refund dispatch and webhook regression tests continue to pass.

## 7. Release gates

No production deployment from this build until:
1. Supabase schema and Auth configuration have been verified.
2. Migration is additive, reviewed, tested against a staging copy, and has a rollback plan.
3. RLS and server-side permission tests pass.
4. Customer/employee separation and shared identity tests pass.
5. POS auth/refund regression tests pass.
6. Preview deployment is verified with non-production credentials.
7. Production secrets and redirect/webhook configuration are verified without disclosing values.

## 8. Current disposition

This commit records the implementation gate and exact audit requirements. It does **not** claim that customer/employee sign-in, shared identity, roles, RLS policies, account freezes, or audit logging are newly implemented by Build 011.09.

The next code change must be based on verified live Supabase schema/provider information, not inferred table or function names. After that verification, implement the canonical identity adapter and server-side authorization before adding the customer and employee sign-in screens.
