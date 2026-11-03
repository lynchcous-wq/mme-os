# Supabase application connection foundation

## Status

This branch now includes Supabase SSR/browser client dependencies, public environment validation, browser/server/admin client factories, an employee sign-in screen, session validation middleware, and a server-side employee relationship gate on the catalog workspace.

This is an application scaffold, not a verified live connection. No Supabase project has been configured or contacted from this branch. SQL migrations remain unapplied, and the app has not been built or tested in a runtime environment.

## Environment

Copy `.env.example` to `.env.local` and set:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` or `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server-only; never expose to browser code)

Never commit real keys. Rotate any key that has been exposed in an untrusted location.

## Client boundaries

- `lib/supabase/client.ts`: browser session client; database access remains governed by RLS.
- `lib/supabase/server.ts`: cookie-aware session client for Server Components and Route Handlers.
- `lib/supabase/admin.ts`: privileged server-only client. Use only after validating the user's session with the session client. Derive actor UUID from `auth.getUser()`; never accept it from a request body, query string, or client state.
- `middleware.ts`: validates employee-area sessions with `auth.getUser()` and redirects unauthenticated visitors to sign-in.
- `app/employee/catalog/page.tsx`: additionally checks active employee relationship and the global employee-access freeze before rendering the workspace. Missing configuration, missing records, or database errors fail closed.

## Current limitations

- Middleware verifies identity, not employee permission grants. The catalog page and draft-creation API check active employment and the global freeze; the draft API additionally calls the server-only authorization function for `catalog.create`.
- `POST /api/employee/catalog` calls a server-only transaction that creates the draft, attaches optional HTTPS media URL metadata, and writes the `draft_created` audit event atomically. Binary uploads/storage integration are not implemented.
- No logout/session-revocation workflow or account provisioning UI exists yet.
- CEO identity must be provisioned out-of-band after verification; it is not inferred from email, user metadata, or client input.
- The service-role client must never be imported into client components.

## Required before employee access is enabled

1. Confirm the intended Supabase project and configure environment variables in a secure deployment environment.
2. Apply migrations in a dedicated test project first and run the SQL verification scripts.
3. Test draft creation, submission, reviewer return, creator-only revision, stale-version conflict, immutable revision snapshots, approval and publication against a dedicated Supabase test project.
4. Verify transaction rollback, stale-version conflicts, and concurrent transition behavior in the test project.
5. Enforce permissions and object scope for every write/read action; never rely on hidden UI controls.
6. Add logout, session revocation, provisioning, customer/employee relationship separation, and audit tests.
7. Verify termination, suspension, permission revocation, global freeze, self-approval rejection, and unauthorized publication.
8. Only then enable production catalog workflows and connect approved products to the customer storefront.


## Product correction and revision workflow

- Reviewers with `catalog.return` permission can return an unapproved pending product with required correction notes.
- The original creator can load their returned drafts and revise them with `catalog.edit` permission.
- Revision requests include the expected product version; stale edits return a conflict rather than silently overwriting newer data.
- A revision clears prior approval/publication metadata and returns the product to draft status; the creator must submit it again.
- Prior product fields are snapshotted in the append-only `product_catalog_revisions` table and a revision event is appended.
- The snapshot, product update, and audit event are now performed by one database transaction function; verify rollback and concurrency behavior before production.


## Atomic catalog workflow transactions

Migrations `20261103000600_atomic_catalog_workflows.sql`, `20261103000700_atomic_catalog_submission_and_publish_guard.sql`, and `20261103000800_atomic_catalog_draft_creation.sql` introduce server-only PostgreSQL functions for reviewer return, approval, publication, employee revision, submission, and initial draft creation. Each function locks the target product row, validates the transition and server-derived actor, updates product state, and writes its immutable event (and, for revisions, the prior-version snapshot) inside one database transaction. A failure in any step rolls back the entire function call.

The corresponding API handlers now call these transaction functions rather than issuing separate product and audit requests. The service-role key remains server-only; the API derives actor identity from the validated Supabase session. The SQL functions are executable only by `service_role`, not browser roles.

The new structural test checks function existence, SECURITY DEFINER status, service-role-only grants, audit writes, revision snapshot writes, and row locking. It has not been run against a database. A dedicated test project is still required for behavior, rollback, concurrent requests, permission revocation, and migration-order tests.


## Atomic draft creation and submission

Migrations `20261103000700_atomic_catalog_submission_and_publish_guard.sql` and `20261103000800_atomic_catalog_draft_creation.sql` complete the transaction-backed employee catalog write path. Draft creation now inserts the product, optional HTTPS media metadata, and initial audit event in one function transaction. Submission now locks the draft, confirms the authenticated creator and submission permission, transitions it to pending review, and records the event atomically. The publication function also checks that the recorded approver was the CEO or an active employee with an unexpired, unrevoked global approval grant.

The create API derives the actor from the validated Supabase session and sends normalized product fields to the server-only RPC. The new functions remain executable only by `service_role`. Media remains an external URL reference; binary upload to Supabase Storage is not included.


## Migration ordering and safety

Migration versions are unique and ordered from `20261103000100` through `20261103000800`. The correction/revision constraints and indexes were consolidated into the single `20261103000500_catalog_corrections_and_revisions.sql` migration to avoid duplicate Supabase migration versions. The branch was synchronized with the current `main` commit; the PR remains open and in draft.
