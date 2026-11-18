# Build 010.84 — Staff Identity Review and Approval Dashboard

## Scope
- Adds an employee dashboard at `/employee/customer-identity-review`.
- Adds a restricted queue API and decision API.
- Adds permission check `customer.identity.review`; active CEO is permitted only while employee access is not frozen. Other staff need an explicit unrevoked, unexpired grant and active employee relationship.
- Adds service-role-only database decision RPCs.
- Supports moving a request to under review, rejecting it, or approving it against a supplied active MME person UUID.
- Approval revalidates the Supabase Auth email confirmation, prevents a conflicting existing login mapping, writes a verified Supabase login-to-person mapping, and invokes the existing customer portal provisioning function in the same database transaction.
- Request status and reviewer attribution are written to the existing trigger-backed request audit.

## Identity proof requirements
Staff must independently verify the person using authoritative MME records and approved internal procedures. Customer-supplied reference, phone suffix, email equality, or note is not proof. The person UUID must come from trusted MME records; it is not discovered or inferred from the customer input. This dashboard does not expose a public identity lookup endpoint.

## Security
- Browser access uses a validated HttpOnly session; actor ID is derived server-side.
- Queue access and decision RPC are service-role-mediated only after explicit staff authorization.
- No browser-role grants are added to private review or identity tables.
- CEO authority honors the global employee-access freeze.
- Approval blocks non-active person identities and conflicting login mappings.
- Approval creates the login mapping and customer portal link atomically.
- No employee role is granted to the customer.

## Operations and verification
- Add permission grant through the existing authorized MME employee access-governance workflow; do not self-assign.
- Migration has not been applied. Tests have been added but not executed in this environment.
- No Supabase production data, grants, or settings changed. Not merged or deployed.
- Before production: run migration in staging, test authorized/unauthorized/terminated/frozen employee paths, test duplicate and conflicting identity mappings, verify atomic rollback, review audit events, and add API edge rate limiting.
