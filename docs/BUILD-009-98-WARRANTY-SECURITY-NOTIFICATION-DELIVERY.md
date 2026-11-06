# Build 009.98 — Warranty Security Notification Delivery

## Delivered
- Retryable email/SMS delivery outbox associated with alert recipients.
- Resend email and Twilio SMS server-side adapters.
- Per-delivery idempotency keys.
- Worker lease claims using database row locks and SKIP LOCKED.
- Bounded retry count and exponential backoff.
- Provider attempt ledger with error codes, provider references and request IDs.
- Protected batch dispatch endpoint.
- Delivery statuses: queued, sent, delivered, failed and skipped.
- Contract tests and CI workflow.

## Provider configuration
Set server-only environment variables:
- `RESEND_API_KEY`
- `MME_SECURITY_EMAIL_FROM`
- `MME_SECURITY_CEO_EMAIL`, `MME_SECURITY_PRIVACY_EMAIL`, `MME_SECURITY_MANAGER_EMAIL`
- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `MME_SECURITY_SMS_FROM`
- `MME_SECURITY_CEO_PHONE`, `MME_SECURITY_PRIVACY_PHONE`, `MME_SECURITY_MANAGER_PHONE`
- `MME_NOTIFICATION_WORKER_SECRET`

Never expose these values through NEXT_PUBLIC variables or client bundles. Only configure verified, company-authorized recipient addresses and phone numbers.

## Dispatch
POST /api/internal/warranty-security-notifications/dispatch
Header: `x-mme-worker-secret`
Body: `{ "limit": 20 }`

Invoke from a trusted scheduler or operations worker after staging verification. The endpoint is not publicly scheduled by this increment.

## Delivery semantics and safety
Provider acceptance is recorded as sent, not delivered. Provider delivery receipts/webhooks and automatic failover are not yet implemented. A failed provider call is retried with bounded backoff; missing configuration is recorded as skipped and requires operator configuration/requeue. In-app alerts remain available independently. Do not place sensitive evidence contents in email/SMS; messages contain alert summaries and identifiers only.

## Validation
Run `npm run lint` and `npm run test:build009:warranty-security-notification-delivery`. Staging must verify provider account, sender verification, recipient authorization, idempotency, retry limits, secret rotation and failure handling. No production secrets, live sends, migration replay or deployment are claimed.
