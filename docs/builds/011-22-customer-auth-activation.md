# Build 011.22 — Customer identity, confirmation, and activation

## Scope and state

This build adds customer registration, email-confirmation callback handling, and a customer-only sign-in path. It does not change the existing employee sign-in route or customer/employee RLS policies.

The signup flow creates a customer relationship with status `pending` only after the Supabase Auth user is confirmed and the existing `mme_auth_user_identity_created` trigger has created the linked person identity. A pending relationship does not grant customer portal access.

## Authorization invariants

1. Never accept a role, employee status, customer status, or permission from browser input or Supabase user metadata.
2. Customer relationship status is changed only by a server-side operation authorized by a verified MME employee identity and an active role assignment/permission grant.
3. Employee and customer relationships are independent. Suspending or terminating an employee relationship must not silently suspend an independent customer relationship.
4. Preserve RLS self-read policies. Do not add public or authenticated INSERT/UPDATE policies to customer relationships.
5. Never expose the Supabase service-role key to a browser, page bundle, or client-readable environment variable.
6. CEO actions require the CEO permission template's MFA and recent-authentication requirements. The current CEO templates are marked `pending_review`; they are not live grants.
7. Keep identity audit records append-only.

## Verified database contract

- `mme_person_identities`: `id`, `auth_user_id`, `security_status`, creation and lock fields.
- `mme_customer_relationships`: `id`, `person_identity_id`, `status`, `created_at`; unique person identity; valid statuses: `pending`, `active`, `temporarily_suspended`, `frozen`, `archived`.
- `mme_employee_relationships`: unique person identity and employee number; valid statuses include `pending`, `active`, `temporarily_suspended`, `frozen`, `terminated`, `archived`.
- `mme_role_assignments`: links an employee relationship to a role; valid statuses include `pending`, `active`, `revoked`, `expired`.
- `mme_permission_grants`: links to a role assignment and carries resource/action/scope/status.
- Existing customer RLS permits an authenticated user to select only their own active customer relationship, where their person identity is active.
- Existing role and permission RLS is also self-read only.

## CEO bootstrap — mandatory controlled operation

Current production audit found no matching Supabase Auth user for the configured CEO email and no employee relationship, role assignment, or permission grant. The `ceo` role definition exists, but this alone confers no authority.

Do not insert a CEO identity or role assignment merely from an email address. Before any bootstrap:
1. Verify the CEO's identity and mailbox ownership out of band.
2. Invite the user through Supabase Auth's supported administrative invitation flow; require email confirmation.
3. Require enrollment of MFA and verify an MFA-authenticated, recent session.
4. Resolve the resulting Auth user to the trigger-created person identity.
5. Create the employee relationship and CEO role assignment using a reviewed, auditable server-side administrative procedure.
6. Keep all CEO permission templates in `pending_review` until a formal review approves each grant; do not auto-grant the entire template.
7. Record the bootstrap actor, target identity, approved role, approvals, and result in the append-only identity audit.
8. Verify the CEO can sign in and can only perform explicitly approved operations.

No bootstrap has been run. No Auth user, employee relationship, role assignment, or permission grant was created during this build work.

## Activation endpoint acceptance criteria

A future activation endpoint must:
- Require an authenticated MME employee session.
- Resolve the employee from the server-verified Auth subject, active person identity, active employee relationship, active CEO role assignment, and explicit approved permission grant for customer relationship status management.
- Enforce MFA and recent authentication on the server, not just in the UI.
- Accept only a customer relationship ID and an allowlisted target status.
- Prevent self-approval, unauthorized status transitions, and privilege escalation.
- Use a transaction or narrowly scoped database function with row locking and append-only audit logging.
- Return no service-role credentials or sensitive identity details.
- Have negative tests for unauthenticated, customer-only, employee-only, inactive CEO, pending role, missing grant, missing MFA, stale auth, invalid transition, and cross-customer ID attempts.

## Release gates

- [x] Schema and RLS contracts inspected.
- [x] Customer registration and sign-in UI/API added on feature branch.
- [x] Confirmation callback added and refresh token bound to the same verified Auth user.
- [x] Customer relationship defaults to pending.
- [ ] Add a dedicated test Supabase environment and preview-scoped credentials.
- [ ] Add rate limiting / abuse protection to signup and sign-in.
- [ ] Implement and review CEO bootstrap procedure.
- [ ] Implement permission-checked customer activation endpoint.
- [ ] Add automated unit/integration tests and negative authorization tests.
- [ ] Verify registration, confirmation, sign-in, sign-out, and activation in preview.
- [ ] Obtain explicit approval before production merge or deployment.

## Deployment status

Feature branch: `build-01122-customer-auth-foundation`

Draft PR: [#200](https://github.com/lynchcous-wq/mme-os/pull/200)

No production migration, production account creation, PR merge, or production deployment is authorized by this build.
