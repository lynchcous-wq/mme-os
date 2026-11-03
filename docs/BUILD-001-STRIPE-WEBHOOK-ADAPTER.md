# Build 001 — Stripe Webhook Adapter

**Status:** Edge Function source committed; deployment and live payment testing not performed.

## Endpoint
Deploy as the Supabase Edge Function named stripe-webhook. Configure these secrets in the Supabase project:
- STRIPE_SECRET_KEY
- STRIPE_WEBHOOK_SECRET
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY
- STRIPE_LIVEMODE (exactly true or false)
- STRIPE_EXPECTED_ACCOUNT_ID (required when processing connected-account events; omit for a platform account)

Subscribe the Stripe endpoint to payment_intent.succeeded and payment_intent.payment_failed.

## Security and processing
The function reads the raw body and verifies the Stripe signature before trusting event data. It enforces the configured live/test mode and optional connected-account ID, resolves the PaymentIntent through the server-only order binding table, checks amount and USD currency, hashes the raw payload, and calls the unified mixed-inventory payment RPC using the service role. It never accepts an order ID supplied by the browser.

## Remaining checkout integration
This endpoint is the webhook half of checkout. A separately authenticated server checkout route must create the order, create the Stripe PaymentIntent using the authoritative order total, and bind the PaymentIntent with mme_bind_order_payment_intent before returning a client secret. The binding RPC requires a trusted actor identity UUID; the application must resolve that from its verified session, never accept it from an untrusted request body. Do not enable live checkout until that route, webhook deployment, database migrations and end-to-end tests are complete.

## Operational note
The function returns a retryable 500 when database processing fails. Recorded amount/currency/reservation mismatches return a successful acknowledgement with a review outcome, preventing endless Stripe retries while leaving the order unpaid and stock protected according to the database processor's result.