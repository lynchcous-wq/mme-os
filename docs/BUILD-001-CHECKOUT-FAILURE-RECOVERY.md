# Build 001 — Checkout Failure Recovery

## Purpose

Recover expired checkout reservations only after the Stripe PaymentIntent has been reconciled. The worker never releases inventory merely because a local timer expired.

## Components

- Migration: `20261103006700_build001_checkout_failure_recovery.sql`
- Worker: `supabase/functions/checkout-recovery-worker/index.ts`
- Private case ledger: `public.mme_checkout_recovery_cases`
- Per-order atomic release RPC: `public.mme_expire_single_inventory_reservation(uuid)`
- Payment confirmation remains owned by the signature-verified Stripe webhook and `mme_process_unified_order_payment_event`.

## Recovery decisions

| Provider state | Action |
|---|---|
| PaymentIntent succeeded | Do not release inventory. Open recovery case for refund/fulfillment decision. |
| PaymentIntent requires payment method/confirmation/action or processing | Attempt Stripe cancellation; release only after Stripe confirms canceled. |
| PaymentIntent already canceled | Release due reservation atomically. |
| PaymentIntent lookup unavailable | Retain inventory; open unresolved case. |
| PaymentIntent binding missing | Search Stripe metadata by MME order ID. Bind only one exact amount/currency/mode match; otherwise retain inventory and open case. |
| Multiple matching PaymentIntents | No automatic selection; retain inventory and open case. |
| Cancellation fails or status remains non-canceled | Retain inventory and open case. |
| Amount, currency, order metadata or live/test mode mismatch | Retain inventory and open case. |

The database expiry RPC locks the order and reservation, releases aggregate and serialized units in one transaction (including mixed carts), and marks the order/reservation expired. Invariant failures roll back the entire release.

## Required environment secrets

Configure these in the Supabase Edge Function environment, never in source control:

- `MME_CHECKOUT_RECOVERY_SECRET`: random secret at least 32 characters, used as Bearer authentication.
- `STRIPE_SECRET_KEY`: restricted/test or live Stripe key appropriate to the environment.
- `STRIPE_LIVEMODE`: exactly `false` in staging/test and `true` only in approved production.
- Standard `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.

Deploy the `checkout-recovery-worker` Edge Function with JWT verification disabled only because it performs its own dedicated constant-time secret authentication. Protect the secret as a privileged credential and rotate it through an approved change process.

## Scheduling and operations

The worker endpoint is not self-scheduling. Configure an external scheduler or approved Supabase Cron/HTTP job to POST to the deployed function at least once per minute with:

`Authorization: Bearer <MME_CHECKOUT_RECOVERY_SECRET>`

Do not store the bearer secret in a migration, repository, client bundle, URL, or logs. Use the scheduler's encrypted secret store. Alert on non-2xx responses, rising quarantined counts, and open recovery cases. Operations must review successful-payment-after-expiry cases before fulfilling or refunding.

## Release validation checklist

1. Apply all migrations to a fresh local Supabase database.
2. Run the full pgTAP suite and new checkout recovery contract tests.
3. Deno type-check the pricing, checkout, recovery worker and Stripe webhook functions.
4. Test Stripe test-mode cases: canceled intent, successful intent, failed intent, missing binding, duplicate metadata matches, provider timeout, cancellation failure, amount mismatch, and mixed aggregate/serialized stock release.
5. Verify repeated worker invocations are safe and do not double-release.
6. Verify webhook retries are idempotent and late success after expiry creates a refund/fulfillment review rather than silently marking stock sold.
7. Configure secrets and scheduler in staging, then run end-to-end tests before any production rollout.

## Known limitation

If Stripe cannot prove whether a PaymentIntent exists or is canceled, the worker deliberately keeps the reservation active and creates/retries a recovery case. This can temporarily reduce sellable inventory, but avoids releasing stock while a customer may have paid. A human reconciliation process is required for unresolved cases.
