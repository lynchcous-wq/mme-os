# Build 001 — authoritative inventory and order schema

**Status:** Proposed Supabase migration; not applied to any database.

## Tables added

- Store locations and active product catalog records.
- Location-specific on-hand and reserved inventory balances.
- Pending/paid/cancelled/refunded order headers and immutable line snapshots.
- Time-limited inventory reservations and reservation lines.
- Stripe webhook event ledger with unique provider event IDs for duplicate-delivery protection.

## Atomic order creation and reservation

`mme_create_order_and_reserve` is the server-only entry point. It creates a pending order, snapshots current database product prices and condition/SKU/title, records the fulfillment location on each line, calculates line/subtotal/total cents, and calls the reservation function in the same database transaction. It uses an idempotency key plus a stable request fingerprint to return the original order for a retry and rejects reuse with a different request. The current MD5 fingerprint is only a non-security equality aid; it is not used for authentication, authorization, signatures, or payment verification. Tax, fulfillment, and discount amounts must be calculated/authorized by the trusted server before invocation.

`mme_reserve_inventory` is a server-only PostgreSQL function. It:
- accepts an existing pending order and a bounded JSON array of product/location/quantity requests;
- rejects null/invalid, duplicate, inactive, unavailable, serialized, and insufficient-stock lines;
- locks product and inventory rows in deterministic product/location order;
- increments reserved quantities and writes reservation lines in the same transaction;
- limits reservation expiry to 30 minutes;
- rolls back all changes if any requested line fails.

Only the Supabase `service_role` may execute this function. Browser roles have no direct table privileges or RLS policies. Never expose the service-role/secret key to a browser.

## Important boundaries

- The atomic RPC still requires a trusted server adapter to authenticate the customer, calculate tax/fulfillment/discount amounts, and call it. Its idempotency fingerprint is a request-retry aid, not an authentication or authorization control.
- The reservation function does not yet consume, expire, or release reservations. Those require separate transactional functions and payment-state checks.
- Serialized device inventory (IMEI/serial-level units) needs a dedicated unit table and reservation locking before serialized products are enabled for online checkout.
- Customer identity is stored as an opaque UUID pending a reviewed foreign-key integration with Build 004 Identity Matrix.
- Serialized products are deliberately excluded from this aggregate-quantity reservation RPC until an IMEI/serial-level unit ledger and unique unit reservation flow are implemented.
- `service_role` receives explicit table privileges; `anon` and `authenticated` receive none. The service-role credential must remain server-only.
- Tax, shipping rates, discounts, Stripe Checkout Sessions, webhook signature verification, refunds, and reconciliation are not implemented here.

## Required database tests before use

1. One available unit reserved successfully.
2. Two concurrent requests for the last unit: exactly one succeeds.
3. Multi-line request with one insufficient line: no partial reservation remains.
4. Duplicate product/location lines rejected.
5. Inactive product/location rejected.
6. Invalid or overlong expiration rejected.
7. Browser roles cannot select or mutate protected tables or invoke reservation RPC.
8. Duplicate Stripe event IDs rejected by unique constraint.
9. Same idempotency key and same request returns the original order; reuse with changed request is rejected.
10. pgTAP schema smoke tests pass for table presence and service-role/browser-role privileges.

Apply only in a disposable Supabase development project after the Build 004 identity migrations and this migration have been reviewed and ordered. No production checkout until order creation, release/expiry, serialized inventory, Stripe test mode, signed webhooks, and reconciliation pass.
