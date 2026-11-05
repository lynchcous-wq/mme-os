# Build 009.36 — POS Financial Provider Adapter & Live Synchronization Engine

Status: implementation committed to a review branch. Database migration replay, TypeScript checks, provider sandbox validation and production scheduling remain pending.

## Delivered components
- `supabase/migrations/20261105001160_build009_pos_financial_provider_sync.sql`
- `lib/pos/financial-adapters/stripe-balance-transactions.ts`
- `app/api/cron/pos-financial-provider-sync/route.ts`
- Updated `app/api/pos/financial-connectors/route.ts` to expose sync-run history.
- Updated `app/internal/financial-connectors/page.tsx` with synchronization history.
- Updated `vercel.json` with a five-minute provider sync schedule.
- `tests/build009-pos-financial-provider-sync.test.mjs`
- `npm run test:build009:financial-provider-sync`

## Stripe adapter implemented
The adapter reads Stripe Balance Transactions using the Stripe REST API:
- `GET /v1/balance_transactions`
- Pagination through `starting_after`, bounded to three pages per connector per invocation.
- Connected-account support using the Stripe-Account header when an account ID is configured.
- Server-only API key lookup using the connector's environment-variable reference; fallback name is `STRIPE_SECRET_KEY`.
- Maps charge/payment balance activity to `gross_sale`, refunds to `refund`, disputes to `chargeback`, and processor fees to `processor_fee`.
- Unrelated balance movements are counted as ignored rather than fabricated as sales.
- Amounts remain in Stripe's currency minor units. No PAN, CVV, PIN, or cardholder credentials are requested or stored.

## Durable synchronization and cursor behavior
- One active synchronization run per connector.
- A stale processing run older than 15 minutes is marked failed before a new run is created.
- Each provider page is normalized and staged through the existing Build 009.34 idempotent staging function.
- Page idempotency keys are deterministic from connector, query window and page boundary IDs.
- The provider cursor is advanced only after page staging succeeds.
- Partial pagination retains its continuation cursor; completed windows resume with a ten-minute overlap to reduce the risk of missing late-arriving records.
- A failed run retains the previous cursor so the same page can be safely retried.
- Import jobs remain processed by the separate Build 009.35 worker; provider retrieval is not itself accounting approval.

## Database addition
`mme_pos_financial_sync_runs` records connector, store, provider, run state, query window, continuation cursor, fetched/staged/ignored counts, batch count, safe error code, worker identity and timestamps. RLS is enabled; direct client access is revoked; service access is limited to select/insert/update. The synchronization functions enforce the existing POS financial import permission.

## Required environment configuration
- Existing `CRON_SECRET`
- Existing `MME_FINANCIAL_WORKER_PERSON_ID`
- Existing server-only `SUPABASE_URL` (or `NEXT_PUBLIC_SUPABASE_URL`) and `SUPABASE_SERVICE_ROLE_KEY`
- Stripe secret stored server-side in the environment variable named by connector `credential_reference`, or `STRIPE_SECRET_KEY`
- `MME_FINANCIAL_BUSINESS_TIMEZONE` set to the IANA timezone for the store (defaults to `America/New_York` if omitted)

Never put Stripe secrets into the browser, connector display name, external account reference or logs. Store only the environment-variable name in `credential_reference`. Use a least-privilege Stripe restricted key where the provider configuration permits it.

## Explicit provider coverage boundary
Stripe Balance Transactions are the first live adapter implemented. This build does not yet retrieve internal MME POS sales from the live POS tables, inventory/COGS feeds, subscription platform transactions, or bank feeds. Their APIs, table schemas, credentials, and source-specific mappings must be confirmed before adapters can be safely implemented. No generic connector is reported as synchronized when no adapter exists.

The Stripe adapter does not import payout objects as revenue; payouts are fund transfers and must be handled in cash/settlement reconciliation. It does not automatically approve financial facts, calculate final accounting classifications, or reconcile bank statements. Existing imported facts continue through the Build 009.34/009.35 staging, idempotency, quarantine and worker pipeline.

## Validation required
- `npm run test:build009:financial-provider-sync`
- `npm run test:build009:financial-worker`
- `npm run test:build009:financial-connectors`
- `npm run lint`
- `npm run build`
- Ordered migration replay and concurrency tests.
- Stripe test-mode validation for charge, refund, dispute, fee, pagination, repeated page, delayed record, credential failure and connected-account scopes.
- Confirm the Vercel project supports the configured cron schedule and has all server-only environment variables configured.

No successful CI run, production migration, actual Stripe synchronization, accounting reconciliation or deployment is claimed.
