# Build 004 Security Review — Authorization CI Addendum

**Validated commit:** `7d763218aba7a3b3ac4a46196421fcb30e56dcbd`  
**Workflow:** https://github.com/lynchcous-wq/mme-os/actions/runs/41949398143

## Automated validation: PASS

The complete CI run finished successfully:
- Fresh Supabase startup and complete migration reset.
- Full pgTAP suite, including Build 004 identity foundation and authorization tests.
- TypeScript and production build.
- Supabase Edge Function type-check.

The centralized function `public.mme_authorize_employee_action` is now present. It checks active person security status, active employee relationship, active role, active role assignment, assignment effective window, permission resource/action, and requested scope. Its EXECUTE grant is restricted to `service_role`; browser roles cannot invoke it directly. The migration also adds role-assignment effective-window and JSON-object scope constraints. The new authorization test contains 13 assertions.

## Remaining blockers

Automated database validation does not establish application-wide authorization. The existing Next.js API routes must be inspected and wired to call the authorization decision before privileged reads/writes. The actor ID must be derived from a validated Auth session, never accepted from client input. Scope must be derived from trusted database records.

Still required:
1. Shared server-only authorization helper and route-by-route integration.
2. Negative route tests for locked identity, inactive/terminated employee, missing/revoked/expired grant, inactive role, and wrong scope.
3. Session/token revocation, active-session race handling, and MFA policy.
4. Review of service-role use, privileged RPCs, secrets, function ownership, and SECURITY DEFINER paths.
5. Non-secret audit actor semantics and externally protected audit retention.
6. Human security approval.

## Decision

Database migration and automated tests are green. Keep PR #14 Draft and unmerged. Do not enable Build 007 CRM foreign keys or production identity rollout until the remaining application and session security gates are completed.
