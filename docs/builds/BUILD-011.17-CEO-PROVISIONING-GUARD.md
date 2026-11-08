# Build 011.17 — CEO Provisioning Guard

Status: guarded provisioning function applied to the live Supabase project. The requested account is still pending; no user was created and no admin permissions were granted.

## Verified flow
- Supabase Auth has an `AFTER INSERT` trigger on `auth.users` named `mme_auth_user_identity_created`.
- The trigger calls `public.mme_create_person_identity()`, which inserts the matching `mme_person_identities` row.
- The person-identity insert trigger records an append-only audit event.
- Therefore provisioning must reuse the trigger-created identity rather than create a duplicate.

## Guarded operation
Function: `public.mme_prepare_ceo_provisioning(text, text)`

Inputs: verified email address and assigned employee number.

Checks:
1. Matching Supabase Auth user exists and `email_confirmed_at` is populated.
2. An active MME person identity is linked to that Auth user.
3. The active `ceo` role definition exists.
4. Employee number is supplied and does not conflict with an existing relationship.
5. Existing matching employee/CEO assignment is reused rather than duplicated.

Creates only:
- Employee relationship with status `pending`.
- CEO role assignment with status `pending`.
- Append-only audit event.

It creates **zero permission grants** and does not activate the employee or role assignment. Function execution is revoked from `PUBLIC`, `anon`, and `authenticated`; only `service_role` may execute it. It is intended for a trusted server-side administrative workflow and must never be called from a browser with an exposed service-role key.

## Required remaining work
- Invite and verify `lynchco.us@gmail.com`.
- Obtain/assign the employee number.
- Invoke this function from a trusted server-side process after verification.
- Separately define and review CEO permissions before any role/employee activation.
- Test denial cases, idempotency, audit logging, and account freeze/session revocation.

No Vercel deployment was made.