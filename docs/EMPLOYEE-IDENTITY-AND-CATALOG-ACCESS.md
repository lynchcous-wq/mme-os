# Employee Identity and Catalog Access

**Status:** Security design contract; not an active authentication implementation.

## Identity model

MME OS uses one person identity with independently assigned relationships. A person may have a customer relationship, an employee relationship, or both. Removing or suspending the employee relationship must not disable the person's customer relationship or customer purchase history.

Employee access is a separate, revocable authorization layer:
- Employee status is active, suspended, or terminated.
- Employee role and permission grants are independent of customer account status.
- Termination revokes employee sessions and employee permissions promptly.
- Customer access remains governed by the customer's own account status.
- CEO-level emergency freeze can revoke employee access without deleting identity or customer records.

## Catalog permission matrix

| Action | Employee catalog editor | Catalog reviewer / manager | CEO |
|---|---:|---:|---:|
| Read catalog | Yes, if granted | Yes | Yes |
| Create draft | Yes, if granted | Yes | Yes |
| Edit draft | Own/assigned drafts, if granted | Yes | Yes |
| Submit for approval | Yes, if granted | Yes | Yes |
| Approve or reject | No | Only if explicitly delegated | Yes |
| Publish approved record | No | Only if explicitly delegated | Yes |
| Archive product | No | Only if explicitly delegated | Yes |
| Change role grants | No | No, unless separately delegated | Yes |
| Freeze employee access | No | No, unless separately delegated | Yes |

CEO authority is the default. Delegation must be explicit, scoped, time-bounded where practical, and audited. No employee may approve their own catalog submission. The system must fail closed when identity, role, permission, or approval authority cannot be verified.

## Required server authorization sequence

1. Validate the server-side session with the configured identity provider.
2. Resolve the person identity and active employee relationship.
3. Confirm the employee relationship is not suspended or terminated.
4. Load current role and permission grants from trusted server-side records.
5. Enforce the action permission and object-level scope.
6. For approval/publication, confirm the actor is the CEO or holds an explicit CEO-delegated permission; reject self-approval.
7. Perform the state change and append its audit event atomically.
8. Return only fields authorized for that employee's role.

Client-supplied role names, user IDs, permission flags, approval fields, or catalog status values are never authoritative. Never authorize from hidden buttons or client-side state.

## Session and account lifecycle requirements

- Revoke or invalidate employee sessions on suspension, termination, permission removal, and CEO freeze.
- Re-check authorization on every server request; do not rely solely on a role cached in a browser session.
- Use secure, HTTP-only, same-site cookies and the identity provider's supported CSRF protections.
- Apply rate limits to authentication and sensitive write operations.
- Record actor, target, action, timestamp, reason, request correlation ID, and before/after version in protected audit records.
- Do not delete the person's customer identity when employee access ends.
- Do not permit employee users to grant themselves permissions or change their own approval authority.

## Implementation gate

The repository currently has no selected identity provider, Supabase client, employee relationship schema, role-grant schema, session validation, or permission middleware. This document is a contract for that implementation, not evidence that authentication or authorization is live.

Before enabling any employee write API:
- Select and configure the identity provider and environment secrets.
- Add employee relationship and permission-grant tables with restrictive RLS.
- Implement server-only session validation and authorization helpers.
- Add tests for employee termination while customer access remains active.
- Add negative tests for self-approval, unauthorized publishing, stale sessions, missing roles, and CEO freeze.
- Verify behavior in a dedicated test project before production rollout.
