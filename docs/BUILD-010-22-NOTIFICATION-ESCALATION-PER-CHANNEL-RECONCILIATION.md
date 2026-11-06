# Build 010.22 — Per-Channel Delivery Reconciliation

## Delivered
- Independent escalation delivery record per required channel.
- Append-only channel attempt history with provider, outcome, reference and request ID.
- Idempotent materialization for configured channels.
- Separate leased channel worker claims using SKIP LOCKED.
- Lease-checked channel completion RPC.
- Per-channel retry/backoff and dead-letter state.
- Scheduled worker changed to process one channel job at a time through shared adapters.
- Per-channel accepted, failed and skipped counters.
- Contract tests and CI.

## Worker
The existing one-minute authenticated cron evaluates SLA breaches, materializes dispatch jobs, materializes configured channel jobs, claims a bounded batch and records each provider outcome independently. A channel job uses its channel-delivery UUID as the provider idempotency key.

## Required configuration
Existing Build 010.21 configuration remains required: CRON_SECRET, worker UUID, Supabase service role, provider secrets and MME_ESCALATION_DISPATCH_CHANNELS.

## Operational boundaries
- A provider accepted response is not proof of final handset receipt; receipt webhooks and human acknowledgement remain distinct signals.
- Configure and apply the migration before enabling the updated cron.
- Channel-level completion is recorded separately; validate parent dispatch finalization against skipped and dead-letter channels before production rollout.
- No migration, CI/test run, provider send, cron activation or deployment was performed or verified.

## Validation
Run `npm run lint` and `npm run test:build010:notification-escalation-per-channel-reconciliation`. Exercise partial success, per-channel retries, dead-letter, skipped recipient, duplicate cron calls, provider failover and lease recovery.
