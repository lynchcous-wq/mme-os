# Build 009.35 — POS Financial Import Worker & Verified Webhook Intake

Status: implementation committed to a review branch. Production migration, CI, scheduled execution and provider sandbox validation remain pending.

## Delivered components
- `supabase/migrations/20261105001150_build009_pos_financial_import_worker.sql`
- Repair to Build 009.34 connector migration SQL syntax on this branch.
- `app/api/cron/pos-financial-import/route.ts` — Vercel Cron GET/POST worker endpoint.
- `app/api/webhooks/stripe/financial/route.ts` — Stripe connected-account signature verification and event receipt.
- `vercel.json` — five-minute cron schedule.
- `tests/build009-pos-financial-import-worker.test.mjs`
- `package.json` — `npm run test:build009:financial-worker`

## Worker pipeline
1. Vercel Cron invokes `/api/cron/pos-financial-import` every five minutes.
2. The route verifies `Authorization: Bearer $CRON_SECRET`.
3. A dedicated MME employee service identity is configured with `MME_FINANCIAL_WORKER_PERSON_ID`; it must remain active, employed, unfrozen and hold a global `pos.finance.report.import` permission grant with scope `{}`.
4. The worker expires exhausted jobs, discovers eligible staged batches and enqueues them.
5. It claims up to ten jobs per invocation using PostgreSQL `FOR UPDATE SKIP LOCKED`, a random lease token and a 180-second lease.
6. It invokes the existing Build 009.34 batch processor, which imports through the Build 009.32 financial fact function.
7. It finalizes completed or completed_with_quarantine jobs. Failures use bounded exponential backoff; eight attempts lead to dead-letter state.
8. If a worker crashes, an expired lease can be recovered. Idempotency at the financial-fact layer prevents duplicate business effects on retry.

## Database additions
- `mme_pos_financial_import_jobs`: one worker job per staged batch, lease, attempts, retry schedule and terminal state.
- `mme_pos_financial_worker_events`: append-only worker lifecycle audit.
- `mme_pos_financial_webhook_events`: provider event ID/type, connected account reference and SHA-256 payload digest only.

Functions:
- `mme_pos_authorize_financial_worker`
- `mme_pos_enqueue_financial_import_jobs`
- `mme_pos_claim_financial_import_job`
- `mme_pos_finish_financial_import_job`
- `mme_pos_expire_financial_import_jobs`
- `mme_pos_record_financial_webhook_event`

All new tables have RLS enabled, direct client access revoked and server-side service-role access only.

## Stripe webhook intake
- Endpoint: `/api/webhooks/stripe/financial`
- Verifies `Stripe-Signature` HMAC-SHA256 with timestamp tolerance (300 seconds) and constant-time digest comparison.
- Requires a unique active Stripe connector matching the connected-account ID.
- Uses provider event ID for idempotent receipt.
- Stores event metadata and payload digest only; raw webhook body is not persisted.
- The route acknowledges receipt; it does not yet retrieve the underlying Stripe object or translate the event into financial facts.

## Environment configuration required
- `CRON_SECRET`: high-entropy secret used to authorize scheduled invocations.
- `MME_FINANCIAL_WORKER_PERSON_ID`: dedicated active MME service identity with least-privilege global import grant.
- `SUPABASE_URL` (or `NEXT_PUBLIC_SUPABASE_URL`) and `SUPABASE_SERVICE_ROLE_KEY`: server-only values.
- `STRIPE_WEBHOOK_SECRET`: signing secret for the configured Stripe connected-account webhook endpoint.

Never expose service-role keys, cron secret or webhook secret to client bundles. The service identity must be dedicated to worker operations; do not reuse an employee's everyday login.

## Important integration boundary
This build executes batches that have already been staged in the normalized import format. It does not yet implement provider API polling, live Stripe transaction retrieval, POS vendor adapters, inventory/subscription adapters, bank feeds, automatic source-cursor advancement, schedule configuration per provider, webhook-to-financial-fact mapping, or provider-object backfill. Those are the next adapter-runtime phase. A webhook event being received is not evidence that its payment or payout has been reconciled.

## Validation required
- `npm run test:build009:financial-worker`
- `npm run test:build009:financial-connectors`
- `npm run test:build009:financial-reporting`
- `npm run lint`
- `npm run build`
- Ordered Supabase migration replay, worker concurrency/lease-expiry/retry/dead-letter tests, webhook signature replay/tamper tests and Stripe connected-account sandbox verification.
- Confirm Vercel project supports configured cron cadence and that all server-only environment variables are present.

No successful CI run, production migration, live cron execution, Stripe event delivery or deployment is claimed.
