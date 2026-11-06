# Build 010.35 — Workforce Lifecycle & Automated Access Provisioning

## Delivered
- Workforce lifecycle case ledger for onboarding, transfer, promotion, leave, return and termination.
- Per-case HR/IT task tracking with owner, due date and completion attribution.
- Role provisioning request ledger for grant, change and revoke actions.
- Approval/rejection records and execution status fields.
- Employee equipment custody and return ledger.
- Administrative API and workforce lifecycle dashboard.
- Audit events for lifecycle operations.

## Identity and enforcement boundaries
- Person IDs are references to the canonical MME workforce identity; staging must verify the existing `mme_person_identities(person_id)` key and intended employee lifecycle semantics.
- This build records access provisioning requests and approvals only. It does not alter Supabase Auth roles, revoke sessions, deactivate accounts or manage devices.
- A verified person-to-auth mapping, approved identity-provider adapter and execution confirmation are required before automatic access provisioning or termination revocation.
- Asset custody records do not prove endpoint/device-management enforcement.

## Validation and rollout
- Run `npm run test:build010:workforce-lifecycle`, `npm run lint`, and `npm run build`.
- Apply migration in staging after Build 010.34; verify foreign-key compatibility, RLS, service-role grants, task lifecycle and audit persistence.
- Not merged, migrated or production deployed.
