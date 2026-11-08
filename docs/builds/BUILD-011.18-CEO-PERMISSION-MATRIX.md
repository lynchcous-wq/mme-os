# Build 011.18 — CEO Permission Matrix

Status: permission-template catalog applied and verified. **No CEO permissions were granted to an account.**

## Purpose
Define an explicit, reviewable least-privilege proposal for the CEO role. This catalog is metadata only; the runtime authorization layer does not automatically consume it, and it does not insert rows into `mme_permission_grants`.

## Proposed CEO matrix (all pending review)
| Resource | Action | Scope / guard |
|---|---|---|
| executive.dashboard | read | MME organization |
| employees.directory | read | MME organization |
| employees.relationships | read | MME organization |
| employees.relationships | manage_status | Active, suspended, frozen, terminated states only |
| identities.security | lock | Cannot target own identity |
| identities.security | unlock | Secondary approval; cannot target own identity |
| roles.assignments | read | MME organization |
| permissions.grants | read | MME organization |
| audit.identity | read | Immutable audit history |
| finance.reports | read | Sensitive fields masked by default |
| inventory.catalog | read | MME organization |
| orders.sales | read | Minimum-necessary customer data |

All entries require MFA and recent authentication. Every row starts `pending_review`. No write access to money movement, payment credentials, payroll, or permission grants is proposed in this initial matrix.

## Security posture
- New table: `public.mme_role_permission_templates`.
- RLS enabled; no client policies.
- All table privileges revoked from `PUBLIC`, `anon`, and `authenticated`.
- Only `service_role` receives table privileges.
- Unique key prevents duplicate role/resource/action/version templates.
- No trigger or function copies templates into live grants.
- No permission grant rows were created.
- CEO role assignment remains pending until the Auth account is invited and email-confirmed.

## Next gates
1. Review and approve the proposed permission matrix.
2. Invite and verify the CEO Auth account.
3. Provision employee and role records in pending state.
4. Implement server-side authorization checks that enforce MFA, recent-auth, scope, self-target denial, and secondary approval.
5. Add tests proving each allow/deny case before converting approved templates into grants.

No Vercel deployment was made.