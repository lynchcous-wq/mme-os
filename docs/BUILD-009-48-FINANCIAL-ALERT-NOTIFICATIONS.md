# Build 009.48 — Executive Financial Alert & Notification Engine

## Purpose
Create a controlled, deduplicated alert layer over Build 009.45 settlement exception cases and Build 009.46 financial risk snapshots.

## Alert sources
- High/critical settlement exceptions.
- Overdue settlement exceptions.
- Latest high/critical financial intelligence snapshot per store and currency.

## Routing
Subscriptions are store-scoped and support executive, Finance and store-manager audiences with in-app or email channel preferences. Executive subscription administration requires the separate settlement approval permission. Recipients must be active identities. Critical exception alerts route to executive and Finance subscriptions; high/overdue alerts route to Finance subscriptions. Risk alerts route to executive and Finance subscriptions.

## Lifecycle
Alerts are deduplicated by immutable source identifier and alert code. Recipients receive unique inbox/outbox rows. Acknowledgment records actor and timestamp. Open alerts can be escalated through bounded SLA levels. Event history is append-only.

## Delivery boundary
The notification outbox supports in-app and email delivery channels. Queueing records work for a separately deployed worker; it does not claim that email was sent. Provider integration, retries against a real provider, bounce handling and push delivery are separate follow-on work.

## RPCs
- `mme_pos_manage_financial_alert_subscription(location_id, actor_person_id, recipient_person_id, audience_role, channel, enabled)`
- `mme_pos_generate_financial_alerts(location_id, actor_person_id)`
- `mme_pos_acknowledge_financial_alert(alert_id, actor_person_id, notes)`
- `mme_pos_escalate_financial_alerts(location_id, actor_person_id)`
- `mme_pos_queue_financial_alert_deliveries(location_id, actor_person_id, batch_size)`

## Security
All tables use RLS and deny direct client-role access. RPCs require store-scoped permission checks. Executive routing administration requires settlement approval permission. The notification inbox is exposed through a security-invoker view, but access is granted only to service_role in this migration.

## Validation
Run `npm run lint`, `npm run test:build009:financial-alert-notifications`, plus financial command center, intelligence, settlement exception and settlement integrity suites. Replay ordered migrations and test idempotency, recipient routing, role boundaries, active-user validation, acknowledgment, escalation, outbox concurrency, and delivery failure handling.

## Rollout boundary
Implementation branch only. No production migration, scheduled scanner, email provider integration, mobile push, or live notification delivery is claimed.
