# Build 001 — Authenticated Checkout PaymentIntent Creation

**Status:** Mixed-cart Edge Function source committed; deployment and Stripe runtime tests remain outstanding.

The `create-checkout-payment` Supabase Edge Function validates the Supabase access token using `auth.getUser()`, then sends the authenticated user and requested cart/fulfillment details to the trusted MME pricing service. That service must resolve the MME customer identity from the verified user, revalidate current product/location/serialized-unit eligibility, and calculate tax, discounts, shipping or pickup charges. It returns canonical item identifiers and fulfillment snapshots; browser prices are never trusted.

The Edge Function validates the pricing response, calls the service-role-only `mme_create_mixed_order_and_reserve` RPC, reads the resulting authoritative order total, creates one Stripe PaymentIntent using an order-derived idempotency key, and binds the PaymentIntent to the order before returning its client secret. Serialized lines require a valid unit UUID and quantity one. Exact approved origins and Stripe live/test mode are enforced.

Required secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_LIVEMODE` (`true` or `false`), `MME_CHECKOUT_PRICING_URL`, `MME_CHECKOUT_PRICING_SECRET`, and `MME_CHECKOUT_ALLOWED_ORIGINS` (comma-separated exact storefront origins).

If PaymentIntent creation or binding fails after stock reservation, the order requires automated expiry/reconciliation. Never enable live checkout before migrations, secrets, deployment, SQL tests, Deno checks, and end-to-end Stripe test-mode validation.
