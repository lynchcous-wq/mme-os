# MME OS Supabase Test Gate

This is a pre-production verification procedure for the product catalog and employee access foundation.

## Safety boundary

- Use a dedicated, disposable Supabase project or local Supabase instance. Do not use production.
- Do not paste service-role keys, database passwords, access tokens, or connection strings into chat, source files, issues, or pull requests.
- Keep `SUPABASE_SERVICE_ROLE_KEY` server-side only. Never use it in browser code or a `NEXT_PUBLIC_*` variable.
- Do not provision the CEO identity until the account has been independently verified. The migration intentionally leaves the CEO unset and privileged operations fail closed.
- Do not enable live catalog publication, customer checkout, Stripe, payroll, or payment collection as part of this test.

## Apply migrations in order

Apply every file in `supabase/migrations/` in ascending 14-digit version order. Stop on the first error. Do not skip or manually reorder migrations.

After migration application, verify:
- All expected catalog, employee access, permission, audit, and revision tables exist.
- RLS is enabled on every protected table; employee access and revision tables also have FORCE RLS.
- Browser roles have no direct policies or execute grants for server-only authorization/workflow functions.
- `employee_security_settings` contains exactly one singleton row and `ceo_user_id` is null before controlled provisioning.

## Structural SQL checks

Run these scripts against the test database after all migrations:
- `supabase/tests/product_catalog_foundation.sql`
- `supabase/tests/employee_access_control.sql`
- `supabase/tests/employee_authorization_engine.sql`
- `supabase/tests/atomic_catalog_workflows.sql`

These checks are structural assertions, not substitutes for behavioral tests.

## Required behavioral scenarios

1. **Fail-closed startup:** with CEO unprovisioned, every catalog operation is denied.
2. **Employee status:** suspended and terminated employees cannot use catalog permissions; customer access remains independent.
3. **Grant scope:** no grant, wrong permission, wrong product scope, expired grant, and revoked grant are denied; valid active grants work.
4. **CEO controls:** provision only the verified CEO; CEO freeze blocks all employee catalog operations; unfreeze restores only otherwise-authorized access.
5. **Draft creation:** valid create succeeds once with one audit event; invalid category, SKU, condition, tracking mode, specifications, and non-HTTPS media fail without partial rows.
6. **Creator ownership:** only the creator can submit a draft or revise a returned draft.
7. **Separation of duties:** submitter cannot approve their own product; an authorized reviewer can approve; an unauthorized employee cannot approve.
8. **Publication gate:** publishing before approval fails; a revoked or terminated delegated approver cannot authorize publication; CEO-approved or currently authorized delegated approval can proceed.
9. **Corrections:** return requires meaningful notes; revision stores a prior immutable snapshot; stale versions fail with a conflict; resubmission creates the expected audit event.
10. **Audit integrity:** event and revision update/delete attempts fail; successful transitions write exactly one corresponding event.
11. **Atomicity:** force an audit insert failure and confirm the associated state transition rolls back.
12. **Concurrency:** race two approvals, two submissions, and two revisions for the same product; only one valid state transition should win.
13. **HTTP boundary:** unauthenticated requests return 401; unauthorized requests return 403; oversized bodies return 413; malformed JSON returns 400; invalid UUIDs return 400.
14. **Identity integrity:** send forged actor IDs in request bodies and confirm the server ignores them and uses the validated session identity.

## Evidence required before closing this gate

Record the test project identifier (not its secrets), migration versions applied, SQL test output, behavioral test results, authorization matrix, rollback results, concurrency results, and CI commit SHA. Redact all personal data and credentials.

A green GitHub build alone does not satisfy this gate. Do not merge or deploy based only on structural SQL checks.
