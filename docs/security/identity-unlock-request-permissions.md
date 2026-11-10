# MME Identity Unlock Request — Permission Audit and Decision Workflow

Audit target: Supabase project `cyatezcfjvewdnibthox` (MME OS production project)
Audit scope: `public.mme_identity_unlock_requests`, its RLS policies, grants, constraints, and related database functions.
Audit type: read-only. No grants, policies, functions, rows, or schema were changed.

## Actual MME database findings

### Table columns
- `id uuid NOT NULL DEFAULT gen_random_uuid()`
- `target_identity_id uuid NOT NULL`
- `requested_by_identity_id uuid NOT NULL`
- `reason text NOT NULL`
- `status text NOT NULL DEFAULT 'pending'`
- `approved_by_identity_id uuid NULL`
- `approved_at timestamptz NULL`
- `created_at timestamptz NOT NULL DEFAULT now()`

### Constraints
- Primary key on `id`.
- Foreign keys from target and requester to `mme_person_identities(id)`, with delete restricted.
- Foreign key from `approved_by_identity_id` to `mme_person_identities(id)`, with delete restricted.
- Status allowlist: `pending`, `approved`, `rejected`, `cancelled`.
- Request reason must be non-empty after trimming.
- Approver cannot equal requester.

### RLS and grants
- RLS is enabled.
- No RLS policies currently exist on this table.
- No table-level or column-level grants were found for `anon` or `authenticated`.
- `service_role` currently has table-level SELECT, INSERT, UPDATE, DELETE and other standard owner-like operational privileges. This is a server credential and must never be exposed to browser code.
- `postgres` has owner-level privileges.
- There are no table triggers on `mme_identity_unlock_requests`.
- No dedicated unlock decision function currently exists.
- The identity audit table has append-only protections; preserve them.

## Difference from the Bolt screenshot

The screenshot describes broad `anon` and `authenticated` table grants being revoked and then replaced by column-limited grants. The current MME database audit does **not** show those broad grants. It shows no grants for either browser role and broad server-only `service_role` privileges.

Therefore, do not copy Bolt's SQL blindly into MME. First confirm Bolt is connected to this exact Supabase project. The MME database is already denying direct browser-role table access at the grant layer; adding column-level grants would be a security regression unless a specific, reviewed workflow requires them.

## Required safe workflow

1. Customer/employee browser submits a request through a server endpoint or a narrowly scoped RPC; it cannot set `status`, `approved_by_identity_id`, or `approved_at`.
2. Server verifies the requester's Supabase session and resolves the requester identity from `auth.uid()`.
3. Server validates target identity and reason, then creates a `pending` request.
4. A reviewer screen may list pending requests only after server-side authorization is verified.
5. Decision operation accepts only request ID, decision (`approved` or `rejected`), and a non-empty decision rationale.
6. A SECURITY DEFINER function performs the transition atomically, with a fixed empty search_path and fully qualified object names. It derives reviewer identity from `auth.uid()`; it must not trust a reviewer ID supplied by the browser.
7. The function verifies active identity, active employee relationship, approved role assignment, explicit permission grant for identity unlock decisions, MFA assurance, and recent authentication. Do not infer authority from email, user metadata, or a role name alone.
8. Lock the request row, require current status `pending`, prevent self-approval, and update decision columns only within the function.
9. Append an immutable identity audit event with actor, target, request, decision, rationale, and timestamp. Audit insertion must be atomic with the decision.
10. Grant EXECUTE only to the intended authenticated role after all checks are implemented and tested. Keep direct table write grants revoked for browser roles.

## Build/release gates

- [x] Read-only inspect of actual MME table columns, constraints, grants, RLS policies, and triggers.
- [x] Confirm no browser-role grants exist on the unlock-request table.
- [x] Confirm no dedicated decision function exists.
- [ ] Confirm Bolt project is connected to the same Supabase project ID.
- [ ] Define and approve the explicit permission key and reviewer eligibility.
- [ ] Implement request-submission function/API with server-derived requester identity.
- [ ] Implement SECURITY DEFINER decision function with MFA/recent-auth checks and immutable audit.
- [ ] Add reviewer queue UI behind server authorization.
- [ ] Add tests for anonymous, customer-only, employee-only, pending/revoked role, missing grant, stale session, no MFA, self-approval, duplicate decision, and invalid transition.
- [ ] Verify in isolated preview environment.
- [ ] Production migration only after review and explicit approval.

No production database changes were made in this audit.
