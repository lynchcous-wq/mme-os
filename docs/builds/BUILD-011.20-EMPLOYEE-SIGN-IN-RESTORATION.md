# Build 011.20 — Employee Sign-In Route Restoration

Status: implementation committed to an isolated preview branch; the current Vercel preview build is blocked/queued and live Auth verification is pending.

## Defect
The public homepage linked to `/employee-sign-in`, but the active Build 011.19 application tree did not contain that App Router page. This produced a Next.js route-level 404 before authentication could run.

## Additive implementation
- Added canonical `/employee-sign-in` page.
- Added compatibility alias `/employee/sign-in`.
- Added server-side Supabase password sign-in endpoint.
- Employee access is granted only after resolving the Supabase Auth subject to an MME person identity and confirming an active row in `mme_employee_relationships`.
- Access and refresh tokens are stored in HttpOnly, SameSite=Lax cookies; no token is returned to browser JavaScript.
- Sign-in responses use no-store cache headers and generic credential errors.
- Added same-origin enforcement for state-changing sign-in/sign-out requests.
- Sign-out calls the Supabase Auth logout endpoint before clearing local cookies.
- No client-side employee role claim or user-editable metadata is trusted.

## Scope and limitations
- This restores the missing route and provides employee identity verification; it does not create Auth users or employee records.
- No automatic CEO/admin grant is issued. Existing role and permission enforcement remains authoritative for protected operations.
- A successful sign-in message confirms an active employee identity only; it does not imply the employee dashboard or every protected module is complete.
- Customer account routes and customer sign-in are not modified by this build.
- No database schema migration or production data mutation is included.

## Release gates
1. Confirm the connected Supabase project has the required Auth URL/key configuration in Vercel server environment variables. Never expose or log secret values.
2. Confirm `mme_resolve_person_for_auth_subject` and `mme_employee_relationships(person_identity_id,status)` match the current live schema.
3. Run TypeScript/build checks and preview route checks.
4. Test invalid credentials, customer-only account denial, active employee acceptance, inactive/terminated employee denial, cookie flags, refresh behavior and logout.
5. Do not promote to production until live employee test fixtures exist and these checks pass.

## Deployment disposition
A Vercel preview deployment was observed for an earlier branch commit (not the final implementation commit); its state remained QUEUED and no build logs were available. A manual deployment request was rejected by Vercel's daily deployment API limit (retry after 24 hours). The final implementation commit is therefore not yet confirmed deployed. The project also has no Auth users at the time of the live read-only check, and the Supabase environment variables currently visible for production are not available to this new preview branch. Do not expose production credentials to a preview deployment merely to test the route. Production deployment is not authorized by this build record.
