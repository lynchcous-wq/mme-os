# Build 010.23 — Provider Receipt Webhooks & Reconciliation

## Delivered
- Provider receipt event ledger with provider/event idempotency.
- Signed webhook ingress route: `POST /api/webhooks/notification-receipts/[provider]`.
- Provider normalization for Resend, Twilio, Telnyx, PagerDuty and configured push callback payloads.
- Payload size limit, timestamp checks where supported and signature gate.
- Service-role-only receipt ingestion RPC.
- Exact provider/channel/reference correlation; missing or unknown references remain unmatched.
- Duplicate event suppression.
- Delivery status reconciliation and parent dispatch terminal-state calculation.
- Contract tests and operational documentation.

## Provider setup
Configure each provider's webhook URL using its provider name segment. Set provider-specific signing secrets/keys and the public callback base URL for Twilio signature verification. Ensure provider callbacks include a stable provider message reference matching the outbound adapter's recorded reference.

## Security and rollout gates
- Configure and validate the provider's actual signature format and key rotation procedure before enabling callbacks.
- Telnyx, PagerDuty and custom push webhook formats must be verified against the exact account configuration and current provider docs.
- Receipt events that cannot be matched by exact provider reference are retained as unmatched; they are not guessed onto a delivery.
- Provider "delivered" receipt is distinct from human acknowledgement.
- Apply both migrations before enabling webhooks.
- No provider configuration, migration, tests, live callback or production deployment was executed or verified.

## Validation
Run `npm run lint` and `npm run test:build010:notification-provider-receipt-webhooks-reconciliation`. Exercise invalid signatures, replayed event IDs, stale timestamps, unknown references, out-of-order events, duplicate callbacks, delivered receipts, permanent failures and retry transitions.
