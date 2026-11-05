# MME OS

Greenfield storefront and operations platform foundation for Much More Electronics.

## Current milestone

Responsive storefront, database-backed catalog/cart, authenticated checkout UI, Stripe Elements integration, server-side pricing handoff, inventory reservation and signed webhook processing are present in the integration branch. Runtime deployment, connected secrets, customer sign-in configuration, and end-to-end payment verification remain environment-dependent and must be validated before production use.

## Stack

- Next.js App Router
- React
- TypeScript
- CSS

## Run locally

Requires Node.js 20.9+ and npm.

```bash
npm install
npm run dev
```

Open http://localhost:3000.

## Next milestones

1. Database-backed products, stock, and CEO pricing approval.
2. Customer identity and separate employee/CEO permissions.
3. Complete checkout runtime validation, Stripe test-mode payment verification, and payment/order reconciliation.
4. Internal system integrations, security, analytics, and production verification.

Do not use the sample catalog as real inventory or pricing. Do not enable live payments until order creation, webhook processing, idempotency, and reconciliation are implemented and tested.

## Checkout configuration

The checkout UI requires `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`. The Supabase `create-checkout-payment` Edge Function additionally requires `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_LIVEMODE=false` for test mode, `MME_CHECKOUT_PRICING_URL`, `MME_CHECKOUT_PRICING_SECRET`, and `MME_CHECKOUT_ALLOWED_ORIGINS`. Never expose service-role or Stripe secret keys to browser code. The trusted pricing endpoint must independently validate the authenticated user, product and serialized-unit identifiers, store, price, stock, fulfillment details, taxes and discounts. A browser payment response does not complete an order; the signed Stripe webhook and server-side reconciliation remain authoritative.

The new checkout route is a draft implementation. Keep Stripe in test mode until the full migration chain, Edge Function deployment, pricing service, environment configuration, Deno checks, database tests and end-to-end payment tests pass. No live-payment enablement is authorized by this source change.
