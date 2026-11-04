# Build 001 — Stripe Webhook Adapter

**Status:** Webhook and authenticated mixed-cart checkout Edge Function source committed; deployment and real payment testing not performed.

## Endpoint and secrets

Deploy as the Supabase Edge Function named `stripe-webhook`. Configure:
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `STRIPE_LIVEMODE` (exactly `true` or `false`)
- `STRIPE_EXPECTED_ACCOUNT_ID` when processing connected-account events

Subscribe to `payment_intent.succeeded` and `payment_intent.payment_failed`.

## Processing and safeguards

The function verifies the exact raw request body with Stripe's signature before trusting event data. It enforces configured live/test mode and optional connected-account identity, resolves the PaymentIntent through the server-only order binding table, checks amount and USD currency, hashes the raw payload, and calls the unified mixed-inventory payment RPC using the service role. It never trusts an order ID supplied by the browser.

The checkout counterpart, `create-checkout-payment`, validates the Supabase user, obtains canonical prices and item identifiers from the trusted MME pricing service, atomically reserves aggregate and serialized stock through the mixed-cart order RPC, creates one PaymentIntent for the authoritative order total, and binds it before returning a client secret. Both functions remain source-only until deployed and configured.

## Required verification

Run Stripe test-mode scenarios for aggregate, serialized and mixed carts; insufficient inventory rollback; duplicate checkout idempotency; successful and failed payments; webhook replay; amount/currency mismatch; and late success after reservation expiration. Verify that mismatches are durably recorded for review and that retryable database failures return non-2xx. Do not enable live checkout until migrations, secrets, deployment, SQL tests and end-to-end verification are complete.
