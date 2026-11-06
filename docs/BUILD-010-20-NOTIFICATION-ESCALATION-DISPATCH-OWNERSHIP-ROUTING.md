# Build 010.20 — Notification Escalation Dispatch & Ownership Routing

## Delivered
- Escalation dispatch queue keyed by escalation and target role.
- Idempotent materialization from overdue acknowledgement escalation records.
- Queue claim RPC using row locks and SKIP LOCKED.
- Worker lease ownership checks and completion RPC.
- Exponential retry with dead-letter after five attempts.
- Incident ownership ledger and ownership-transfer audit events.
- Role-checked assignment/transfer with CEO/CIO executive override audit marker.
- Destination role and user existence validation.
- Authenticated incident command API and dashboard.
- Contract tests and CI workflow.

## Dashboard and API
- `/warranty/security-intelligence/incident-command`
- `/api/warranty/security-intelligence/incident-command`

## Worker integration required
A trusted scheduled worker must call `mme_security_notification_materialize_escalation_dispatch()`, then claim rows using `mme_security_notification_claim_escalation_dispatch(worker_id, limit)`. It must route each row through the existing notification delivery subsystem and complete with `mme_security_notification_finish_escalation_dispatch(dispatch_id, worker_id, success, error)`. The existing RPC is a queue interface; no external notification is sent by this build itself.

## Boundaries
- No cron/scheduler or worker process is deployed/configured.
- Role targets are sourced from the alert's configured target_roles. Escalation tier-specific routing policy and automatic owner assignment are not yet implemented.
- Ownership transfer requires an authorized role; a supplied owner UUID is validated against auth.users.
- No production database migration, CI/test run, provider delivery or deployment has been executed or verified.

## Validation
Run `npm run lint` and `npm run test:build010:notification-escalation-dispatch-ownership-routing`. Verify queue materialization, lease expiry, retries, dead-letter, duplicate materialization, target-role fanout, ownership transfer and executive override.
