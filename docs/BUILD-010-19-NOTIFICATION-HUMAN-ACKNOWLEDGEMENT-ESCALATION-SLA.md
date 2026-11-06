# Build 010.19 — Human Acknowledgement & Escalation SLA

## Delivered
- Alert acknowledgement status, deadline, actor and optional note fields.
- Acknowledgement event and escalation ledgers.
- Database acknowledgement RPC with row locking, assigned-role enforcement and idempotent repeat behavior.
- Pending escalation cancellation after acknowledgement.
- SLA claim RPC that marks expired pending alerts overdue and creates a first-level escalation record.
- Authenticated role-scoped acknowledgement API.
- Executive acknowledgement dashboard with deadline, overdue, acknowledged and closed views.
- Contract tests, CI and runbook.

## Dashboard and API
- `/warranty/security-intelligence/acknowledgements`
- `/api/warranty/security-intelligence/acknowledgements`

## SLA behavior
New alerts inherit acknowledgement deadlines from their policy's `acknowledge_within_minutes`. Existing alerts are backfilled from policy configuration where available. The protected SLA RPC marks pending alerts overdue and creates a level-one escalation ledger row. Acknowledgement records the authenticated actor and cancels pending/processing escalation rows.

## Important boundaries
- A protected scheduler must invoke `mme_security_notification_claim_acknowledgement_sla`; scheduling is not configured here.
- This build records escalation work but does not itself send an escalation notification or assign a new owner. Delivery of escalations is a subsequent integration.
- Role assignment currently compares JWT app-metadata roles with alert target_roles. It does not establish individual assignment beyond those roles.
- The dashboard uses the existing sessionStorage access-token convention from the security operations pages.
- No database migration, tests/CI, scheduler, or production deployment was executed or verified.

## Validation
Run `npm run lint` and `npm run test:build010:notification-human-acknowledgement-escalation-sla`. Test acknowledgement races, unassigned roles, duplicate acknowledgements, overdue cutoffs, cancelled escalation jobs, and scheduler retries.
