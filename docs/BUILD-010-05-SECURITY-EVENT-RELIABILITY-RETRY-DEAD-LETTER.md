# Build 010.05 — Security Event Reliability, Retry & Dead-Letter Engine

## Delivered
- Durable task queue with unique (event, task type) idempotency.
- Queue states: pending, processing, succeeded, retry_wait and dead_letter.
- Atomic worker claim RPC using row locks and two-minute leases.
- Bounded exponential retry schedule, capped at six hours.
- Configurable maximum attempts, default eight.
- Attempt history and delivery receipts.
- Signed internal worker endpoint.
- Ingestion now enqueues correlation work.
- Authorized queue inspection and dead-letter replay endpoint.
- Delivery reliability dashboard at `/warranty/security-intelligence/delivery`.
- Contract tests, CI and documentation.

## Worker configuration
- `MME_SECURITY_WORKER_SECRET`: server-only secret used by scheduled worker invocations.
- `SUPABASE_SERVICE_ROLE_KEY`: server-only Supabase credential.
- Invoke POST `/api/internal/warranty-security-delivery-worker` with `X-MME-WORKER-SECRET` and optional `X-MME-WORKER-ID`.
- Worker claims up to ten jobs per invocation.

## Replay
POST `/api/warranty/security-intelligence/delivery` with action `replay`, jobId and a reason of at least ten characters. Only dead-letter jobs are eligible. Replay resets attempt count and records a replay receipt.

## Important limitations
- Worker scheduling, secret provisioning/rotation and alert delivery are not configured here.
- The correlation task has a basic worker handler. Notification and reconciliation tasks intentionally fail into retry/dead-letter until their providers/handlers are configured.
- Worker claim/finish uses service-role RPC; validate SQL function privileges and PostgREST exposure in staging.
- Queue replay updates state then writes receipt; if receipt persistence fails, manual reconciliation is required.
- No provider failover, distributed tracing, SLA dashboard or production execution is claimed.
- The worker route file was also committed to the repository default branch during authoring before being added to this feature branch. Review that independent default-branch change separately; it is not part of this feature PR.

## Validation
Run `npm run lint` and `npm run test:build010:security-event-reliability-retry-dead-letter`. In staging test worker lease expiry, concurrent claims, retries, max-attempt dead-letter, replay authorization, receipt persistence and notification/reconciliation failure handling. No tests, migration, deployment or scheduled worker run are claimed.
