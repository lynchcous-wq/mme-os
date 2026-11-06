# Build 010.18 — Notification Provider Receipts & Delivery Reconciliation

## Delivered
- Provider receipt ledger with unique provider event IDs and payload digests.
- Receipt-to-delivery correlation by provider and provider reference.
- Resend Svix signature and timestamp verification.
- Twilio callback signature verification using configured public callback URL.
- HMAC-SHA256 verification for pager and push callbacks.
- Receipt deduplication and processing outcome recording.
- Delivery status reconciliation for accepted, sent, delivered, bounced, undelivered, failed and complaint events.
- Monotonic protection against downgrading a delivered message on a later failure callback.
- Receipt ledger in privileged delivery operations API and dashboard.
- Contract tests, CI and runbook.

## Callback endpoint
`POST /api/webhooks/security-notification-receipts?provider=resend|twilio|pager|push`

## Required environment
- Resend: `RESEND_WEBHOOK_SECRET` (Svix signing secret).
- Twilio: `TWILIO_AUTH_TOKEN` and `MME_TWILIO_STATUS_CALLBACK_URL` (exact externally configured callback URL).
- Pager: `MME_PAGER_WEBHOOK_SECRET`.
- Push: `MME_PUSH_WEBHOOK_SECRET`.
- Supabase service-role credentials for receipt persistence.

## Provider setup
Configure Resend and Twilio delivery-status callbacks to the endpoint with the matching provider query parameter. Pager/push receivers must send HMAC-SHA256 of the exact raw request body in `X-MME-Signature: sha256=<hex>`. Send a stable event ID and the exact provider reference returned during dispatch.

## Limitations and safety
- SendGrid, Telnyx and arbitrary pager/push vendor-specific receipt formats are not implemented; the pager/push callback is an MME-defined signed envelope.
- Twilio callback signature depends on the exact public URL; reverse-proxy URL rewriting must be accounted for in the configured value.
- Unmatched receipt events are stored as unmatched and require operational investigation; automatic replay/reconciliation of previously unmatched events is not included.
- Email open tracking is intentionally not treated as delivery confirmation.
- Provider receipt does not prove a human read or acknowledged an alert.
- No external credentials, callbacks, migrations, tests/CI or production deployment have been executed or verified.

## Validation
Run `npm run lint` and `npm run test:build010:notification-provider-receipts-delivery-reconciliation`. Test valid/invalid signatures, timestamp replay, duplicate callback delivery, reference mismatch, out-of-order events, delivered-state protection and provider outage.
