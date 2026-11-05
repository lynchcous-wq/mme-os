# Build 009.43 — Stripe refund dispatch worker

## Scope
Add an authenticated server-side worker that claims only Stripe refund requests from the provider-scoped Build 009.42 queue, submits refunds through Stripe's API, and records only safe provider outcomes.

## Controls
- Requires CRON_SECRET, STRIPE_SECRET_KEY, SUPABASE_URL (or NEXT_PUBLIC_SUPABASE_URL), and server-only SUPABASE_SERVICE_ROLE_KEY.
- Accepts only a bearer-authenticated scheduled invocation; service-role credentials never reach the browser.
- Uses a bounded claim batch and the existing lease token / provider idempotency key.
- Sends connected-account context only through Stripe-Account and the existing provider account reference.
- Never marks a refund completed from the synchronous API response. It records unknown_reconciliation and waits for the signed Build 009.42 webhook to confirm the exact account, payment intent, refund ID, amount and currency.
- Definite non-rate-limit 4xx rejection is marked failed. Network, rate-limit, and 5xx outcomes remain unknown and must be reconciled; never blindly retry.
- Does not log raw provider payloads, credentials, or cardholder data.

## Validation required
Run npm run lint, npm run test:build009:stripe-refund-dispatch, and npm run test:build009:stripe-refunds. Then perform fresh ordered Supabase migration replay, PostgreSQL concurrency/lease tests, Stripe test-mode connected-account refund tests, webhook-before-worker and worker-before-webhook ordering tests, duplicate event tests, and unknown-outcome recovery tests.

## Rollout boundary
This is an implementation branch only. Do not configure production cron or enable live refunds until Build 009.42 is reviewed, migrations are replayed, all tests pass, and Stripe sandbox verification succeeds. No production deployment or live refund is claimed.
