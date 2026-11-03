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

- Middleware verifies identity, not employee permission grants. The catalog server page currently checks active employment and global freeze; feature-level authorization must be enforced by server Route Handlers before any write or privileged action.
- The employee catalog editor remains a local-only preview; no product writes, uploads, or publication API exist.
- No logout/session-revocation workflow or account provisioning UI exists yet.
- CEO identity must be provisioned out-of-band after verification; it is not inferred from email, user metadata, or client input.
- The service-role client must never be imported into client components.

## Required before employee access is enabled

1. Confirm the intended Supabase project and configure environment variables in a secure deployment environment.
2. Apply migrations in a dedicated test project first and run the SQL verification scripts.
3. Implement server Route Handlers that validate `auth.getUser()`, load employee status, and invoke the authorization function using the verified user ID.
4. Enforce permissions and object scope for every write/read action; never rely on hidden UI controls.
5. Add logout, session revocation, provisioning, customer/employee relationship separation, and audit tests.
6. Verify termination, suspension, permission revocation, global freeze, self-approval rejection, and unauthorized publication.
7. Only then replace the employee catalog preview with authenticated, persisted workflows.
