# Build 001 — Mixed-Cart Order Creation

**Status:** Checkout Edge Function integration committed on `foundation/build001-mixed-cart-checkout`; database migration and SQL contract tests remain source-only, not deployed or runtime-tested.

The service-role-only `mme_create_mixed_order_and_reserve` RPC creates one pending order, one shared inventory reservation, and order-line snapshots for aggregate and serialized cart entries. Aggregate lines use `product_id`, `location_id`, and `quantity`, omitting `serialized_unit_id`. Serialized entries include `serialized_unit_id` and require `quantity=1`; the unit must match the product/location and be in stock. The RPC uses database catalog prices, snapshots serial/IMEI and condition details, locks records, and reserves both stock types within the same transaction. Validation or stock failures roll the transaction back.

The checkout Edge Function now calls this mixed-cart RPC after obtaining the trusted pricing response. It validates UUID-shaped product, location, and optional serialized-unit identifiers, and enforces quantity one for serialized units. The existing flow then reads the pending order's authoritative total, creates one Stripe PaymentIntent, validates it against the order, and binds it for webhook processing.

The unified payment webhook processor is intended to consume or release both reservation types atomically. Payment processing has **not** been tested or verified. No payment test was run as part of this integration.

**Remaining release work:** apply the migration in a controlled Supabase environment; execute the SQL contract tests; verify the Deno and Next.js CI jobs; validate the trusted pricing service contract; and complete security and operational review. Do not treat the source changes as deployed or production-ready until those checks and required approvals are complete.
