# Build 010.68 — Notifications & Automation Engine

## Implemented
- Notification preference, template and event-rule schema.
- Scheduled notification queue for email, SMS and in-app channels.
- Bounded concurrent-safe batch claim using `FOR UPDATE SKIP LOCKED`.
- Attempt tracking, retry backoff, provider response metadata and audit events.
- Authenticated staff queue API; marketing queue requests require a customer with current channel-specific marketing consent and non-suppressed CRM status.
- Secret-protected dispatch worker that calls a separately configured dispatcher with an idempotency key.
- Admin dashboard and acceptance contract tests.
- RLS and service-role-only data access.

## Configuration / release blockers
- Set `MME_NOTIFICATION_WORKER_SECRET`, `MME_NOTIFICATION_DISPATCH_URL`, and `MME_NOTIFICATION_DISPATCH_TOKEN` only after selecting and security-reviewing a delivery provider/adapter. No provider is included or provisioned.
- Configure and test a scheduler to invoke the worker. No cron schedule is deployed by this commit.
- Dispatcher must implement idempotency, validate channel/recipient, return provider/message identifiers, and distinguish accepted, delivered, bounced, suppressed and rejected states. Current worker records successful dispatcher HTTP response as `sent` (accepted), not delivered.
- Delivery webhooks and provider signature verification are not implemented.
- Event rules and templates are data registers only; no event consumer evaluates rules, interpolates templates, schedules renewals, payment reminders, low-stock alerts or CRM follow-ups yet.
- Customer preferences are schema only and are not yet enforced by queue RPC; marketing uses current consent ledger and CRM suppression. Implement atomic consent evaluation, preference enforcement, withdrawal precedence, jurisdiction policy, quiet hours, frequency caps and opt-out handling before live use.
- In-app delivery/read state, push notifications, customer self-service preferences, per-store/team permissions, PII masking, retention and encryption need implementation.
- Queue API uses service role; implement idempotent enqueue RPC and authorization/tenant scoping. Add rate limiting and abuse protection.
- Validate retries, worker crash recovery, duplicate webhooks, concurrent workers, provider outages and dead-letter handling.

## Validation
Run `npm run test:build010:notifications`, communications/CRM/identity/security suites, `npm run lint` and `npm run build`. Tests not executed, migration not applied, scheduler/provider not configured, not merged or production deployed.
