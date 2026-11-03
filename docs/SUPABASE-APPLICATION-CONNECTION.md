# Supabase application connection foundation

## Status

This branch adds the Supabase SSR/browser client dependencies and client factories. It does not connect to a live project until deployment environment variables are configured. SQL migrations remain unapplied; employee login and authorization are not yet enabled.

## Environment

Copy `.env.example` to `.env.local` and set:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` (a Supabase anon or publishable key)
- `SUPABASE_SERVICE_ROLE_KEY` (server-only; never expose to browser code)

Never commit real keys. Rotate any key that has been exposed in an untrusted location.

## Client boundaries

- `lib/supabase/client.ts`: browser session client; database access must remain protected by RLS.
- `lib/supabase/server.ts`: cookie-aware session client for Server Components and Route Handlers.
- `lib/supabase/admin.ts`: privileged server-only client. Use only after validating the user's session with the session client. Derive the actor UUID from `auth.getUser()`; never accept it from a request body, query string, or client state.

## Required before employee access is enabled

1. Confirm the intended Supabase project and configure environment variables in a secure deployment environment.
2. Apply migrations in a dedicated test project first and run the SQL verification scripts.
3. Implement a session refresh proxy/middleware compatible with the installed Next.js version.
4. Add server Route Handlers that call `auth.getUser()`, load employee relationship status, and invoke the authorization function using the verified user ID.
5. Add login, logout, session revocation, customer/employee relationship separation, and audit tests.
6. Verify termination, suspension, permission revocation, global freeze, self-approval rejection, and unauthorized publish behavior.
7. Only then replace the employee catalog preview with authenticated, persisted workflows.

No service-role client may be imported into client components. CEO identity must be provisioned out-of-band after verification; it is not inferred from email, user metadata, or client input.
