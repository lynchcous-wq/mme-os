# Build 010.81 — Customer Registration and Verified Account Provisioning

## Scope
- Adds a customer registration page at `/account/register`.
- Adds a server-mediated Supabase Auth signup endpoint at `POST /api/auth/register`.
- Validates same-origin requests, JSON content type, email shape, full name length, and a 12–128 character password.
- Does not return auth tokens, set browser session cookies, assign employee permissions, or link a registration to an MME person identity.
- Keeps customer account authorization dependent on the existing trusted provisioning process and active identity checks in Build 010.80.

## Required Supabase configuration
- Email confirmations must be enabled in Supabase Auth.
- Configure the production Site URL and allowed redirect URLs to the MME domain before enabling public registration.
- Configure SMTP/email delivery and test confirmation links end-to-end in staging.
- If Supabase returns an immediate session from signup, the endpoint fails closed and does not issue MME session cookies. Note: the provider may have created the auth user; an administrator must review Supabase Auth settings before retrying.

## Identity safety
Registration metadata is untrusted customer-supplied data. It is not a verified MME customer identity and cannot be used to create or link `mme_person_identities`, `mme_customer_account_links`, or `employee_relationships`. A verified customer who has an existing in-store profile must be linked through an authorized, audited MME provisioning workflow. This build does not provide that privileged workflow.

## Security and operations
- No passwords or auth tokens are logged or returned.
- Responses are no-store and errors avoid disclosing whether an email is already registered.
- Rate limiting, CAPTCHA/bot defense, abuse monitoring, password recovery, and MFA remain deployment prerequisites/follow-on work. Enforce rate limits at the edge/API gateway before exposing this endpoint publicly.
- Verify Supabase confirmation behavior, duplicate-email behavior, allowed redirect URLs, email delivery, and post-confirmation sign-in against staging.

## Verification status
Contract tests are added but have not been executed in this environment. No migration is introduced. No Supabase settings were changed. This build is not merged or deployed and is not production-ready until staging verification and rate limiting are complete.
