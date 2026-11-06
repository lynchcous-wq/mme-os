# Build 010.86 — Customer Profile Management

## Scope
- Adds `/account/profile` and authenticated profile API.
- Supports preferred display name (1–80 printable characters), email-notification preference, and SMS-notification preference.
- Keeps sign-in email read-only; email changes require a separate verified account workflow.
- Does not edit legal name, phone number, MME person identity, account ownership, or customer links.
- Writes profile change audit entries with changed fields and before/after state.
- Customer can read only their own profile; profile updates require matching authenticated Supabase identity and verified email.

## Security and boundaries
- RLS protects profile rows by auth user ID.
- Audit table has no browser grants.
- Update RPC checks auth.uid() equals requested owner and requires verified Auth email.
- API enforces same-origin JSON PATCH and bounded values.
- SMS preference is a stored preference only; no phone verification, consent enrollment, or SMS delivery is triggered.
- Marketing messages and mandatory service notices are outside these preference toggles.

## Verification
Contract tests added but not executed in this environment. Migration not applied, not merged or deployed. Staging must test cross-customer isolation, audit immutability, invalid input, session refresh, and verified-email behavior.
