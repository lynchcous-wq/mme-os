# Build 001 — Mixed-Cart Order Creation

**Status:** Database migration, contract tests, and checkout Edge Function integration committed. Not deployed or runtime-tested.

The service-role-only `mme_create_mixed_order_and_reserve` RPC creates one pending order, one shared inventory reservation, and immutable order-line snapshots for aggregate and serialized cart entries. Aggregate lines use `product_id`, `location_id`, and `quantity`; serialized entries additionally include `serialized_unit_id` and require quantity 1. The RPC verifies product/unit/location eligibility, snapshots database-owned catalog prices and device details, locks records in deterministic order, and reserves both stock types in one transaction. Any validation or stock failure rolls the transaction back.

The authenticated `create-checkout-payment` Edge Function now calls this mixed-cart RPC with canonical item lines from the trusted pricing service, reads the authoritative order total, creates one Stripe PaymentIntent, and binds it to the order before returning the client secret. It validates the Supabase session, idempotency key, request shape, approved browser origins, Stripe test/live key mode, and PaymentIntent mode. Browser-supplied prices are never authoritative.

The Stripe webhook verifies the raw-body signature, resolves the server-side payment binding, checks amount and currency, and calls the unified payment processor. The database processor consumes or releases aggregate and serialized reservations atomically and deduplicates provider events.

Required checkout secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_LIVEMODE`, `MME_CHECKOUT_PRICING_URL`, `MME_CHECKOUT_PRICING_SECRET`, and `MME_CHECKOUT_ALLOWED_ORIGINS`. The pricing service must derive customer identity from the authenticated user and revalidate current catalog, unit, location, tax, discount, and fulfillment data.

**Release gate:** Apply migrations in timestamp order to a dedicated test project; deploy checkout and webhook functions with test-mode secrets; configure Stripe test webhook events; execute aggregate-only, serialized-only, mixed-cart, insufficient-stock rollback, idempotent retry, payment success/failure, expired-reservation late-success, amount mismatch, and webhook replay tests. Keep live mode disabled until all gates pass. PaymentIntent creation/binding failures require reservation expiry and reconciliation.
