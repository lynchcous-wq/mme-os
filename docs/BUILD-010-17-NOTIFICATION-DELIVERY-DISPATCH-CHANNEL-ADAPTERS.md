# Build 010.17 — Notification Delivery Dispatch & Channel Adapters

## Delivered
- Durable delivery jobs and provider-attempt history.
- Email, SMS, pager and push channel support.
- Resend/SendGrid email adapters with provider failover.
- Twilio/Telnyx SMS adapters with provider failover.
- Signed HTTPS webhook adapters for pager and push platforms.
- Per-delivery idempotency keys for supported providers/webhooks.
- Concurrent-safe database claim worker with expiring leases.
- Bounded exponential retry and dead-letter status.
- Recipient routing from approved notification policy snapshots.
- Re-queue newly routed recipients when alert escalation changes target roles.
- Authenticated dispatch worker endpoint.
- Privileged delivery queue API and operations dashboard.
- Contract tests, CI and operational documentation.

## Dashboard
`/warranty/security-intelligence/delivery-dispatch`

## Worker
`POST /api/internal/security-notification-dispatch`

Header: `x-mme-notification-dispatch-secret`

## Environment configuration
- `MME_NOTIFICATION_DISPATCH_SECRET`
- Email: `MME_EMAIL_PROVIDER`, `RESEND_API_KEY`, `SENDGRID_API_KEY`, `MME_SECURITY_EMAIL_FROM`, and role-specific `MME_SECURITY_*_EMAIL`.
- SMS: `MME_SMS_PROVIDER`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `MME_SECURITY_SMS_FROM`, `TELNYX_API_KEY`, `MME_TELNYX_SMS_FROM`, and role-specific `MME_SECURITY_*_PHONE`.
- Pager: `MME_PAGER_WEBHOOK_URL`, `MME_PAGER_WEBHOOK_SECRET`.
- Push: `MME_PUSH_WEBHOOK_URL`, `MME_PUSH_WEBHOOK_SECRET`.

## Production boundaries
- Provider acceptance is not proof of final recipient delivery. Provider callbacks/receipts are not implemented in this build; accepted jobs remain accepted until a future receipt integration updates them.
- Pager and push require an MME-compatible webhook receiver. The signed payload uses HMAC-SHA256 and a stable delivery idempotency key.
- Email/SMS recipient mapping is role-based environment configuration. No customer-facing or general employee directory lookup is performed.
- No external provider credentials were supplied or tested. No actual messages were sent.
- Schedule the worker using a protected scheduler. Do not expose its secret to browsers.
- No migration execution, tests/CI execution or production deployment is claimed.

## Validation
Run `npm run lint` and `npm run test:build010:notification-delivery-dispatch-channel-adapters`. Test provider timeouts, duplicate requests, lease expiry, escalation recipient additions, dead-letter recovery, webhook signature verification and delivery receipt reconciliation.
