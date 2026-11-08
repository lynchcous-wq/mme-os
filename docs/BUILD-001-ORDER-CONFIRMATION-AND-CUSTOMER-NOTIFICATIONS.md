# Build 001 — Paid Order Confirmation, Customer History & Notifications

## Implemented components

- `20261103006800_build001_paid_order_confirmation_and_customer_history.sql`
  - `mme_finalize_paid_order_fulfillment(order_id, system_actor_identity_id)` creates the fulfillment row only after the payment processor has marked the order paid.
  - Queues one idempotent `order_paid` email.
  - `mme_get_my_order_history()` scopes results to `auth.uid()` -> active MME identity -> active customer relationship; the caller cannot provide another customer's identity ID.
- Stripe webhook invokes finalization after the signature-verified event is processed. It checks the persisted order status and repeats finalization on duplicate webhook deliveries, so transient finalizer errors can recover without consuming inventory twice.
- `20261103006900_build001_fulfillment_status_notification_automation.sql` adds an after-update trigger to queue email for picking, shipped, ready-for-pickup, delivered, picked-up and exception transitions.
- `supabase/functions/customer-notification-worker/index.ts` claims leased outbox rows and sends email through Resend using the stable outbox idempotency key.
- `app/account/page.tsx` now supports existing-customer magic-link sign-in and renders the caller's own order history, items, shipping tracking and pickup status.

## Required environment

Configure these in Supabase Edge Function secrets:

- `MME_STRIPE_SYSTEM_ACTOR_ID`: UUID of the dedicated, active MME system identity permitted by internal operational policy. It must exist before payment webhooks can finalize fulfillment.
- `MME_CUSTOMER_NOTIFICATION_SECRET`: random bearer secret at least 32 characters.
- `RESEND_API_KEY`: Resend API key for the verified MME sending domain.
- `MME_EMAIL_FROM`: verified sender, e.g. an approved address at the MME domain.
- Existing `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.

The browser requires the existing `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Configure Supabase Auth email-link redirects to the approved production domain and the staging domain; do not allow broad wildcard redirects.

## Scheduling

Deploy `customer-notification-worker` and schedule authenticated POST calls at least once per minute using the scheduler's encrypted secret store:

`Authorization: Bearer <MME_CUSTOMER_NOTIFICATION_SECRET>`

The worker uses leased claims, bounded retry and Resend's idempotency header. Monitor queue depth, failed/suppressed rows and worker non-2xx responses. Do not place credentials in SQL migrations, client code, URLs or logs.

## Scope and customer privacy

- This release sends email only. SMS is not enabled until MME has approved a compliant SMS provider, consent capture, opt-out processing and message templates.
- Customer history RPC uses the authenticated session identity; it does not accept an arbitrary customer ID.
- Customer-facing history intentionally omits internal notes, staff identities, full shipping address, payment secrets and fraud/risk metadata.
- Payment success remains determined by the signed Stripe webhook and database payment processor, not by the browser redirect.

## Validation before release

1. Fresh local Supabase migration replay through 06900.
2. pgTAP checks for paid-only finalization, idempotency, customer isolation and notification transition mapping.
3. Node contract tests and Next TypeScript/production build.
4. Deno checks for the webhook and notification worker.
5. Staging Stripe test-mode success, duplicate webhook, late webhook, failed payment and finalizer retry.
6. Resend test delivery for each template, provider timeout, 429, 5xx, idempotent resend and exhausted retry.
7. Existing-customer magic-link sign-in, unauthorized account access, cross-customer isolation and tracking-link validation.
8. Configure secrets, verified sender domain and scheduler in staging, then run end-to-end tests.

No production migration, secret, Resend sender, scheduler, Stripe endpoint or deployment is configured by these source commits alone.
