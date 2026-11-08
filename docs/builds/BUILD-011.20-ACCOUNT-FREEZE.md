# Build 011.20 — Administrative Security and Account Freeze

Status: applied to live Supabase. No user accounts or permissions were activated.

## Freeze
`private.mme_freeze_identity(target_identity_id, actor_identity_id, reason)` requires a distinct active actor and reason; prohibits self-freeze; locks the target identity; deletes all current Supabase Auth sessions; and writes an immutable audit event. Build 011.19's authorization evaluator denies locked identities. Customer relationships and employee relationship status are not changed.

## Two-person unlock
1. A distinct active administrator requests unlock with a reason.
2. A different active identity approves. Neither requester nor target can approve.
3. Identity is restored to active and audit event is written. Old sessions remain revoked; fresh sign-in is required.

## Security
- Unlock request table has RLS enabled, no client policies, and service_role-only grants.
- Security functions are in private schema, SECURITY DEFINER with empty search_path, callable only by service_role.
- Audit remains append-only.
- Customer relationships are untouched.

## Critical server integration boundary
These are trusted backend primitives. Actor identity must be derived by the server from a verified user JWT, never browser-supplied. Before calling a routine, server must enforce `mme_authorize('identities.security','lock'|'unlock', target)`, MFA and recent authentication. Unlock approval must come from a different authenticated administrator. Never expose service_role key to clients.

## Validation limits
Auth user count is currently zero, so session revocation and full actor/approver flows cannot be exercised with real accounts. No CEO privileges or active grants were created. No Vercel deployment was made.