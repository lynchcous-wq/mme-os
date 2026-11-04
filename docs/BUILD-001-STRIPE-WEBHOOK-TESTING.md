# Build 001 — Stripe webhook verification tests

## Run the focused Deno tests

From the repository root, with Deno 2 installed and network access available for the pinned imports:

```sh
deno test --node-modules-dir=none supabase/functions/stripe-webhook/index_test.ts
```

The test file covers bounded request-body handling, empty and oversized bodies, SHA-256 hashing, invalid signatures, valid signed events, body-tampering rejection, and stale signature timestamps.

## Run the Edge Function type-check

```sh
deno check --node-modules-dir=none supabase/functions/stripe-webhook/index.ts
```

## CI coverage note

The current GitHub Actions workflow type-checks the webhook function but does not execute this Deno unit-test file. A successful type-check is not evidence that the unit tests have passed. The database pgTAP suite is a separate check and must also complete successfully.

All test credentials and webhook secrets in the unit-test source are synthetic fixtures. Do not replace them with live Stripe credentials.
