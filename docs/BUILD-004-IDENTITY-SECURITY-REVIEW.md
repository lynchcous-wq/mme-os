# Build 004 Identity Foundation — Security Review

**Review target:** `integration/build004-identity-validation`  
**Reviewed commit:** `e06c944c1f275f801cd8e82c670386ae144232d8`  
**Scope:** Static review of the five identity migrations and the Build 004 pgTAP test. This is not a penetration test, runtime authorization verification, or production approval.

## Review outcome

**Status: database foundation validated; authorization rollout remains blocked.**

The fresh-database CI run passed all 93 pgTAP files / 921 tests, including the 29 Build 004 assertions. That proves the migrations apply and the covered database invariants pass. It does not prove that application routes enforce employee/customer authorization or whole-login locks.

## Findings and required gates

### SEC-004-01 — No runtime authorization enforcement is included
**Severity: Critical / release blocker**

The migrations create role assignments, permission grants, employee/customer relationships, and a whole-login security lock. They do not implement a server-side authorization function or middleware that checks all of the following on every protected request:
- authenticated subject maps to exactly one active person identity;
- person identity `security_status = 'active'`;
- employee relationship is active where employee access is required;
- role is active and assignment is active and within its effective time window;
- permission grant is active and matches the requested resource/action;
- requested resource is within both assignment and grant scopes;
- any account, session, device, or emergency security revocation state is honored.

**Required:** implement centralized server-side deny-by-default authorization and negative tests for each missing, expired, revoked, mismatched, or out-of-scope condition. Do not trust client metadata, caller ID, profile appearance, or a submitted employee ID.

### SEC-004-02 — Whole-login lock is a data constraint, not an enforced lock
**Severity: Critical / release blocker**

The security-lock migration constrains the shape of lock state but does not revoke sessions or reject requests. Its comment explicitly delegates enforcement to protected server requests.

**Required:** every authenticated server entry point must check lock state before returning protected data or performing writes. Add session/token revocation and reauthentication orchestration, including race-condition tests for a lock issued during an active session. Customer and employee relationship status must remain independent from whole-login security status.

### SEC-004-03 — Role assignment temporal and scope invariants are incomplete
**Severity: High**

The schema allows `effective_until` to be earlier than or equal to `effective_from`, and `scope` / grant `scope` are unconstrained JSONB. The schema also does not itself guarantee that an assignment is usable only while the employee relationship and role are active.

**Required:** add a check constraint for a null end time or `effective_until > effective_from`; define and validate a strict scope schema; enforce active employee + active role + active assignment + effective window + active grant at authorization time. Add tests for malformed scope, unknown scope keys, expired/future assignments, inactive role, and terminated/suspended employee.

### SEC-004-04 — Runtime database privilege model needs explicit verification
**Severity: High**

The migrations enable RLS and revoke direct client-role privileges. They do not define a dedicated least-privilege runtime database role or prove the privileges of every server-side execution identity. Supabase service-role access bypasses RLS and must not be treated as a substitute for application authorization.

**Required:** document and test the exact runtime database role(s), grants, ownership, SECURITY DEFINER functions, and search paths. Keep service-role credentials server-only. Verify no browser bundle, client response, logs, or error messages expose privileged credentials. Avoid broad service-role use for ordinary user requests.

### SEC-004-05 — Audit actor field must be an identifier, never a secret
**Severity: High**

The audit table contains `actor_service_key text`. Its intended semantics are not defined by the migration. If this field is ever populated with a service-role key or credential, it would create a credential leak in the audit trail.

**Required:** formally constrain this field to a non-secret service identity identifier (for example, a fixed service principal key name or UUID), rename it if necessary to make that unambiguous, and prohibit tokens, API keys, authorization headers, and credential material in all audit fields. Add tests and logging guidance.

### SEC-004-06 — Append-only triggers are not tamper-proof against privileged owners
**Severity: Medium**

The triggers reject UPDATE, DELETE, and TRUNCATE through ordinary table operations. A sufficiently privileged database owner or administrator can alter/drop triggers or otherwise modify the schema.

**Required:** document the trusted-admin threat boundary, restrict schema ownership and migration credentials, export audit events to a separately controlled append-only destination, and alert on trigger/schema/privilege changes.

### SEC-004-07 — Auth trigger execution behavior must be confirmed on the target Supabase/PostgreSQL version
**Severity: Medium**

The migration revokes direct EXECUTE from PUBLIC, anon, and authenticated after trigger creation. The migration comment itself calls for verifying trigger invocation behavior on the target version.

**Required:** retain the passing fresh-database auth-user insertion test and add a test executed under the actual intended auth insertion path and runtime grants before rollout. Do not grant direct client execution as a workaround.

## Existing positive controls observed

- Person identity is separated from customer and employee relationships.
- Customer and employee relationships can coexist for one person identity.
- The Auth insert trigger creates an opaque identity and does not automatically create a customer or employee relationship.
- RLS is enabled on the identity tables.
- Direct anon/authenticated privileges are revoked in the foundation migration.
- Audit UPDATE, DELETE, and TRUNCATE are blocked by triggers in the tested database role context.
- The identity audit actor must be an identity or service identifier; no credential material should be stored.

## Acceptance checklist before Build 007 CRM integration

- [ ] Centralized server-side authorization is implemented and reviewed.
- [ ] Whole-login lock blocks every protected route and write path.
- [ ] Session/token revocation and active-session race tests pass.
- [ ] Customer and employee lifecycle independence is verified through service workflows.
- [ ] Role/permission temporal and scope validation is enforced and tested.
- [ ] Runtime database roles, grants, ownership, and SECURITY DEFINER functions are reviewed.
- [ ] Service credentials are verified server-only and absent from bundles/logs/audit.
- [ ] Audit actor identifier is explicitly non-secret and externally protected audit retention is designed.
- [ ] Auth trigger behavior is verified using the target Supabase/PostgreSQL runtime path.
- [ ] Human security review approves the implementation before merging or enabling CRM foreign keys.

## Decision

Keep PR #14 Draft and unmerged until the critical/high findings are resolved or explicitly accepted by the designated security reviewer. No production deployment, live authentication change, or payment activation is authorized by this review.
