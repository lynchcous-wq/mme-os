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
- `POST /api/employee/catalog` creates a draft product record after validating the session, employee relationship, global freeze, category, input shape, and `catalog.create` authorization. It records a `draft_created` event and can attach an HTTPS media URL as metadata. This is metadata linking only; binary uploads/storage integration are not implemented.
- Draft creation and media/audit writes are separate database requests, not one atomic transaction. If a later step fails, an administrator must reconcile the already-created draft before the employee retries.
- No logout/session-revocation workflow or account provisioning UI exists yet.
- CEO identity must be provisioned out-of-band after verification; it is not inferred from email, user metadata, or client input.
- The service-role client must never be imported into client components.

## Required before employee access is enabled

1. Confirm the intended Supabase project and configure environment variables in a secure deployment environment.
2. Apply migrations in a dedicated test project first and run the SQL verification scripts.
3. Test draft creation, submission, reviewer return, creator-only revision, stale-version conflict, immutable revision snapshots, approval and publication against a dedicated Supabase test project.
4. Convert product update, revision snapshot, and audit event writes into atomic database RPC transactions; verify stale-version conflicts and rollback behavior.
5. Enforce permissions and object scope for every write/read action; never rely on hidden UI controls.
6. Add logout, session revocation, provisioning, customer/employee relationship separation, and audit tests.
7. Verify termination, suspension, permission revocation, global freeze, self-approval rejection, and unauthorized publication.
8. Only then enable production catalog workflows and connect approved products to the customer storefront.
