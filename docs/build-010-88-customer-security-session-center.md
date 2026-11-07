# Build 010.88 — Customer Security Center & Session Management

## Scope
- Adds `/account/security` and authenticated session-security API.
- Shows current authenticated account and a customer-readable MME security event history.
- Adds global sign-out using Supabase Auth `logout?scope=global`; clears local HttpOnly session cookies.
- Records successful password sign-in and global session revocation events in an append-only event ledger.
- Customer may read only their own security events. Browser roles cannot insert/update/delete events.

## Explicit session inventory limitation
The existing MME/Supabase Auth integration does not provide a verified API to list every active device session with trustworthy device, location, or last-active metadata. The dashboard therefore shows current browser session only and does not fabricate a multi-device session list. Global sign-out is provided by the provider's global logout endpoint.

## Security
- Global revocation requires authenticated same-origin POST.
- Event ledger has RLS owner-read policy and append-only trigger.
- Service-role key is server-only; event details are allow-listed and omit IP address and user-agent.
- Existing session cookie values remain HttpOnly; no tokens are returned to the browser.
- Global sign-out revokes refresh sessions; already-issued access JWTs may remain valid until their configured short expiry.
- Event history is MME application-originated, not a complete provider audit stream.

## Verification
Contract tests added but not executed. Migration not applied, not merged or deployed. Staging must verify provider global logout semantics, refresh-token revocation across devices, access-token expiry behavior, event insertion and RLS, and customer-to-customer isolation.
