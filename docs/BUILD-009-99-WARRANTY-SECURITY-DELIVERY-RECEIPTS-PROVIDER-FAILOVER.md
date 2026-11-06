# Build 009.99 — Warranty Security Delivery Receipts & Provider Failover

## Delivered
- Idempotent provider receipt ledger.
- Resend webhook verification using Svix signature and timestamp.
- Twilio callback signature verification.
- Receipt correlation to delivery provider references.
- Delivery-state updates and alert event history.
- Configurable primary/secondary email providers: Resend and SendGrid.
- Configurable primary/secondary SMS providers: Twilio and Telnyx.
- Provider failover after an explicit send failure.
- Payload digest storage instead of raw webhook payload retention.
- Contract tests.

## Configuration
- Email: `MME_EMAIL_PROVIDER=resend|sendgrid`, `RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET`, `SENDGRID_API_KEY`, `MME_SECURITY_EMAIL_FROM`.
- SMS: `MME_SMS_PROVIDER=twilio|telnyx`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TELNYX_API_KEY`, `MME_SECURITY_SMS_FROM`, `MME_TELNYX_SMS_FROM`.
- Telnyx callback verification and SendGrid Event Webhook ingestion are not implemented in this increment. Resend and Twilio are the supported receipt callbacks.
- Configure and test provider-specific callback URLs, signing secrets and verified sender identities before activation.

## Operational boundaries
A provider accepting a message is not proof that a recipient received it. Delivery receipts are processed only for supported Resend and Twilio callbacks. Provider failover occurs only when the primary API call returns a failure; it does not infer a delivery failure from a missing callback. A message accepted by a provider must not be blindly resent because a callback is delayed. In-app alerts remain the independent fallback.

## Validation
Run `npm run lint` and `npm run test:build009:warranty-security-delivery-receipts-provider-failover`. Staging must verify signature validation, timestamp tolerance, duplicate callbacks, callback replay, provider-reference mapping, sender authorization and failover behavior. No production sends, migration replay or deployment are claimed.
