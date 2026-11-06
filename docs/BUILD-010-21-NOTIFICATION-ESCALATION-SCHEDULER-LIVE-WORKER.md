# Build 010.21 — Live Escalation Scheduler & Worker

## Delivered
- Authenticated scheduled worker endpoint: `POST /api/cron/security-notification-escalations`.
- Vercel cron schedule every minute.
- SLA overdue evaluation, escalation dispatch materialization and leased queue claiming.
- Provider dispatch through the shared MME email, SMS, pager and push channel adapters.
- Worker completion under the claimed worker identity.
- Failed delivery attempts return to retry/backoff and eventually dead-letter via the queue RPC.
- Configurable channels and no-success reporting when no provider accepts.
- Contract tests and operational runbook.

## Required environment
- `CRON_SECRET`: secret used by scheduled invocation.
- `SUPABASE_URL` or `NEXT_PUBLIC_SUPABASE_URL`.
- `SUPABASE_SERVICE_ROLE_KEY`.
- `MME_NOTIFICATION_ESCALATION_WORKER_ID`: valid UUID used as worker lease identity.
- `MME_ESCALATION_DISPATCH_CHANNELS`: comma-separated allowed channels, e.g. `email,sms`.
- Provider environment for configured channels, including recipient and sender settings documented in Build 010.17.

## Operations
Vercel invokes the route every minute. The route requires `Authorization: Bearer <CRON_SECRET>`, marks acknowledgement SLA breaches, materializes overdue escalation dispatches, claims up to 20 jobs, and sends via the shared provider adapter. A dispatch is marked successful only if at least one configured channel returns accepted/delivered. Otherwise the queue records a retry or dead-letter outcome.

## Safety and limitations
- Do not enable production cron until provider credentials, sender identities, recipient destinations, worker UUID and secrets are configured and verified.
- Channel list must be explicitly configured; an empty list fails closed.
- One successful channel is sufficient to mark the role dispatch complete; partial-channel outcomes are not yet tracked separately.
- Provider acceptance is not proof of human acknowledgement; receipt webhooks and acknowledgement SLA remain authoritative for those states.
- The cron endpoint is scheduled in source configuration, but actual Vercel deployment, plan eligibility, secret configuration, migration execution, tests and provider sends have not been verified.
- Queue migrations 010.20 must be applied before enabling the worker.

## Validation
Run `npm run lint` and `npm run test:build010:notification-escalation-scheduler-live-worker`. Stage unauthorized invocation, missing environment, empty channels, provider acceptance, all-channel failure, duplicate invocation, lease recovery and dead-letter cases.
