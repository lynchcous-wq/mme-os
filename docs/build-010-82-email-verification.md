# Build 010.82 — Customer Email Verification and Account Activation

## Scope
- Adds a customer-facing verification landing page at `/account/verify-email`.
- Adds `POST /api/auth/verify-email`, which redeems a Supabase email token hash only after an explicit same-origin user action.
- Restricts the endpoint to signup email verification (`type=email)); recovery, invite, magic-link and email-change flows are not accepted.
- Validates the returned access token against Supabase Auth and requires a confirmed email timestamp.
- Discards the returned access and refresh tokens. Verification does not sign the browser in.
- A verified email does not automatically create or link an MME person identity, customer account link, or employee relationship. Normal sign-in and existing trusted identity provisioning remain required.

## Email template and Supabase configuration
Configure the Supabase Confirm Sign Up email template to link to:
`{{ .SiteURL }}/account/verify-email?token_hash={{ .TokenHash }}&type=email`
The Supabase project Site URL must be the MME production origin, and the redirect allow-list must include the exact verification page URL. Configure and test SMTP delivery before enabling public registration.

The verification page deliberately does not redeem the token during GET/page load. Email security scanners commonly prefetch links; a visible button triggers the POST redemption so passive link inspection does not consume the one-time token. Tokens are not placed in application logs or returned to the browser API response. After success, the page removes the token hash from the visible URL.

## Security and operations
- Same-origin JSON POST; bounded token hash; fixed verification type; no open redirect.
- No cookies or customer/employee privileges are created by verification.
- Invalid, expired, reused and provider-rejected tokens receive a safe generic message.
- Add edge/API rate limiting and abuse monitoring before public exposure.
- Test valid, expired, replayed, wrong-type and malformed hashes against staging Supabase, plus actual confirmation-email delivery and link scanning behavior.

## Verification status
Contract tests are added but have not been executed in this environment. No Supabase project settings or email templates were changed. No migration is required. Not merged or deployed; staging validation and rate limiting remain prerequisites.

## Reference
- Supabase email templates: https://supabase.com/docs/guides/auth/auth-email-templates
- Supabase Auth verify endpoint: https://github.com/supabase/auth
