# Build 001 — checkout domain foundation

**Status:** Domain contracts and deterministic validation only. Not a live checkout implementation.

## Implemented in this change

- Strictly parses checkout requests with bounded cart size and quantities.
- Rejects duplicate product identifiers.
- Supports shipping-address and pickup-location request shapes.
- Builds a quote only from server-loaded authoritative product records.
- Does not accept client-submitted price, title, stock, tax, shipping, discount, or total fields.
- Validates server-provided tax and fulfillment charges and calculates integer-cent totals.
- Rejects inactive products, invalid pricing, and insufficient stock.

## Deliberately not implemented

This module does not:
- connect to Supabase or any database;
- authenticate the customer or authorize checkout;
- lock inventory or create a reservation;
- calculate tax or shipping;
- create an order or Stripe Checkout Session;
- process Stripe webhooks, refunds, or reconciliation.

The current browser bag remains a local demo. Do not wire a customer-facing payment button to this module until the server/database adapters and release gates below exist.

## Required next server-side workflow

1. Authenticate customer and enforce account/order permissions.
2. Parse the request with `parseCheckoutRequest`.
3. Load active catalog prices and available inventory from the trusted database.
4. Calculate tax and shipping/pickup charges through approved server-side providers/rules.
5. Build the quote with `buildCheckoutQuote`.
6. In one database transaction, re-check stock and reserve inventory atomically, then create a pending order with immutable line/price/fulfillment snapshots.
7. Create a Stripe-hosted Checkout Session using the server-calculated amount and internal order ID; use a stable idempotency key.
8. Verify Stripe webhooks against the raw body and signing secret; deduplicate provider event IDs in the database.
9. Mark paid only after matching the verified event's payment, amount, currency, and order.
10. Release fulfillment only from the authoritative paid state.

## Acceptance tests still required

- Invalid and duplicate cart lines rejected.
- Client-supplied price fields ignored because the parser never reads them.
- Price changes between browse and checkout use the database price.
- Inactive and insufficient-stock products rejected.
- Tax and fulfillment charges must be valid server calculations.
- Shipping and pickup paths validated separately.
- Concurrent purchase of the last serialized item cannot oversell.
- Stripe test-mode success, failure, expiry, duplicate webhook, invalid signature, out-of-order events, full/partial refund, and reconciliation tests pass.

## Release controls

- Supabase project and disposable development database configured.
- Build 004 identity and RLS policies reviewed and tested.
- Server-only credentials stored in encrypted deployment secrets, never in Git or browser bundles.
- Stripe test-mode end-to-end and webhook verification demonstrated.
- CEO approval before production payment activation.

No database migration, Stripe API call, or production setting is changed by this domain-only foundation.
