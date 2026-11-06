# Build 009.49 — Enterprise Notification Delivery & Communications Infrastructure

## Scope
Provider-neutral delivery outbox for email, SMS, push and in-app notifications; localized/versioned templates; per-user channel preferences and quiet-hour settings; provider routing metadata; retry, dead-letter and delivery health.

## Security
- Provider credentials are not stored in PostgreSQL. Provider routes contain only environment-secret references such as `MME_EMAIL_PROVIDER_API_KEY`.
- A separately deployed worker resolves secret references from approved runtime secret storage.
- RLS is enabled and all direct client access is revoked. Service-role RPCs are the integration boundary.
- Recipient contact resolution must occur inside the trusted delivery worker using the approved identity/contact service. Do not copy email addresses, phone numbers, device tokens or provider credentials into job payloads or logs.
- Quiet hours and channel preferences are stored per person; emergency override policy must be implemented and audited by the orchestrator, not inferred from severity in SQL.

## Channels
Email, SMS, push and in-app. Existing Build 009.48 financial alert notifications can be linked to generic delivery jobs. Push device registration and provider-specific token lifecycle are a later adapter integration.

## Operations
- Versioned localized templates.
- Idempotent enqueue.
- Concurrent-safe batch claim using `FOR UPDATE SKIP LOCKED`.
- Provider-neutral result recording.
- Bounded exponential retry and dead-letter state.
- Per-attempt audit history and channel health summary.

## RPCs
- `mme_notification_enqueue_delivery(...)`
- `mme_notification_set_channel_preference(...)`
- `mme_notification_claim_delivery_jobs(channel, batch_size)`
- `mme_notification_complete_delivery(job_id, provider_code, outcome, provider_message_id, error_code, latency_ms)`

## Required worker behavior
The worker must resolve recipient contact data securely, apply quiet-hour preferences and approved emergency override rules, render the exact stored template version, call the configured provider adapter, redact PII from logs, record the provider outcome, and retry only retryable failures. Provider fallback must be explicit and must preserve the same idempotency key to avoid duplicate sends.

## Validation
Run `npm run lint`, `npm run test:build009:notification-delivery`, and `npm run test:build009:financial-alert-notifications`. PostgreSQL integration tests must cover permissions, recipient identity, template version pinning, duplicate enqueue, concurrent claims, retry caps, dead-letter handling, provider failover idempotency, quiet-hour boundaries and PII redaction.

## Rollout boundary
Implementation branch only. No email/SMS/push provider is configured, no credentials are stored, and no live delivery worker or user-facing settings UI is deployed. Provider adapters and scheduled worker deployment require separate secrets and environment approvals.
