# Build 010.34 — Identity Governance & Privileged Access Management

## Delivered
- Person-linked temporary privileged access request ledger with role, scope, rationale, reviewer and expiry.
- API enforces a maximum 24-hour requested elevation window.
- Approval/rejection workflow records the reviewer and decision.
- Periodic access review ledger records retain, modify, revoke or pending outcomes.
- Emergency freeze request and approval/lift state machine.
- Governance audit ledger.
- Authenticated CEO/CIO/IT administrator API and dashboard.

## Enforcement boundary
- This build records requests and approvals; it does not mutate Supabase Auth claims, revoke sessions, disable accounts or enforce freezes.
- Canonical MME person identity is referenced through mme_person_identities; auth user IDs are stored separately for actors.
- A verified person-to-auth identity mapping and an approved permission/session enforcement adapter are required before activating live elevation, termination revocation or CEO emergency freeze.
- An approved freeze request must not be described as an account frozen until enforcement confirmation is recorded.

## Validation and rollout
- Run `npm run test:build010:identity-governance`, `npm run lint`, and `npm run build`.
- Apply migration in staging after Build 010.33; verify FK compatibility with mme_person_identities, RLS, service-role grants, approval boundaries and audit persistence.
- Not merged, migrated or production deployed.
