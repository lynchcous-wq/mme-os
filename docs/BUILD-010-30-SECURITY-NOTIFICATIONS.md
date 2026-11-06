# Build 010.30 — Enterprise Security Notifications & Communications

## Implementation
- Role-based notification subscriptions for CEO, CIO, IT administrators and managers.
- Severity-aware event fan-out for incident opening, escalation, recovery verification, closure request and closure approval.
- Idempotent event/recipient/channel notification queue.
- Dispatch function reuses Build 009.49 notification templates, recipient preferences, provider routes and delivery outbox.
- Disabled recipient channels are suppressed.
- Missing templates or outbox setup leave an explicit blocked-template status; the incident event remains recorded.
- Delivery health aggregates channel and status without exposing contact data.
- Existing security notification command center is retained; its provider receipt endpoint remains protected by an adapter secret.

## Operations
1. Apply migration in staging after Build 009.49 and Build 010.29.
2. Add active CEO/CIO/IT admin/manager person identities and role/channel subscriptions.
3. Create active templates for `security_incident_event` for each configured channel and locale.
4. Configure provider routes and runtime secrets through existing Build 009 mechanisms.
5. Invoke `mme_security_incident_dispatch_notifications` from a service-role worker on a controlled schedule.
6. Verify provider delivery receipts and retry/dead-letter behavior before enabling external channels.

## Safety and limitations
- No provider credentials are stored in the database.
- No external delivery is claimed by this migration.
- Actual email/SMS/push delivery depends on configured provider adapters and existing delivery worker.
- No incident records are deleted if delivery is blocked.
- Not merged, migrated, or production deployed.
