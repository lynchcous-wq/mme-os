# Build 010.87 — Contact Verification and Account Recovery

## Scope
- Adds authenticated email-change request using Supabase Auth; the existing sign-in email remains active pending provider confirmation.
- Adds phone enrollment and OTP confirmation routes; phone is not considered verified until provider verification succeeds.
- Adds account recovery request with uniform response text to reduce account enumeration.
- Adds recovery-token password reset with bounded password requirements.
- Adds customer contact-verification and recovery pages.
- No MME person identity, customer link, legal identity, or employee role is modified.

## Security boundaries
- Contact mutations require same-origin requests and an authenticated browser session.
- Recovery request is intentionally unauthenticated, validates email shape, and uses a uniform response regardless of account existence.
- Tokens are not written to logs or returned to the browser in API responses. Recovery page accepts a token copied from the configured provider's secure link.
- Supabase Auth delivery, email-change confirmation settings, phone provider configuration, OTP template, redirect allowlists, and rate limiting must be configured and tested in Supabase.
- SMS notification preferences are separate from phone verification and do not enroll a customer in marketing.
- Application-level rate limiting is not included; production must apply edge/provider rate limits and abuse monitoring.

## Verification
Contract tests added but not executed. No Supabase settings or live data changed. Migration not required. Not merged or deployed. Staging must verify provider-specific email-change behavior, phone OTP type/template, recovery deep link/token handling, throttling, token replay, session rotation, and contact-change audit requirements.
