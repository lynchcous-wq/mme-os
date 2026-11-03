# Build 001 — Authenticated Checkout PaymentIntent Creation

Status: additive source committed only; not deployed or tested against Stripe.

The create-checkout-payment Edge Function validates the Supabase access token, delegates customer identity resolution and tax/discount/fulfillment pricing to the trusted MME pricing service, creates and reserves an aggregate-inventory order using the existing database RPC, reads the authoritative database total, creates one Stripe PaymentIntent with an order-derived idempotency key, and binds the PaymentIntent to the pending order.

Required secrets: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, STRIPE_SECRET_KEY, MME_CHECKOUT_PRICING_URL, MME_CHECKOUT_PRICING_SECRET.

The pricing service must return customer_identity_id resolved from the authenticated user, canonical item product/location/quantity lines, tax_cents, fulfillment_cents, discount_cents, and fulfillment_snapshot. Product prices remain database-owned; the order RPC calculates subtotal and total. The endpoint uses the returned order.total_cents for Stripe, not a client or pricing-service total.

This first endpoint supports aggregate inventory only. Serialized and mixed carts are rejected by the existing order/reservation RPC until a unified mixed-mode order-creation transaction exists. If PaymentIntent creation or binding fails after reservation, the order requires automated expiry/reconciliation. Never enable live checkout before migrations, secrets, deployment, and end-to-end test-mode validation.