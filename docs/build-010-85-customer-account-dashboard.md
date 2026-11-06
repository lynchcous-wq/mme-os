# Build 010.85 — Customer Account Dashboard and Profile Management

## Scope
- Adds a private dashboard at `/account/dashboard` and an authenticated no-store API.
- Validates the browser session, exactly one active customer account link, and active person identity.
- Displays verified login email and account status without fabricating profile name, phone, address, or reward balances.
- Reads customer-safe order, fulfillment, refund, warranty, and subscription projections for the linked person only.
- Includes empty states, order totals, shipment tracking, pickup readiness, warranty expiry, refund and subscription status, and sign-out.
- Does not expose internal person/Auth UUIDs or accept a person identifier from the browser.

## Security
- Server derives the customer identity from the authenticated session and active account-link table.
- Every request revalidates active person lifecycle.
- Service-role calls are server-side and scoped to the verified person.
- Responses use no-store caching. No cross-customer lookup or profile mutation endpoint is introduced.
- Existing customer portal RLS remains unchanged.

## Limitations
Profile name, phone, address, rewards, and MME Rewards Card data are omitted until trusted customer-safe sources and field-level disclosure policies are established. Commerce records appear only when upstream projections are populated.

## Verification
Contract tests added but not executed. No migration or production Supabase change. Not merged or deployed. Staging must test customer A/B isolation, suspended/revoked links, inactive identities, pagination, and projection freshness.
