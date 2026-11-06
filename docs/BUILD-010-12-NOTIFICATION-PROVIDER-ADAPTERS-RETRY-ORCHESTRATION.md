# Build 010.12 — Notification Provider Adapters & Retry Orchestration

## Delivered
- Expiring delivery leases to recover abandoned dispatch claims.
- Bounded concurrent-safe notification claim function.
- Per-notification configurable retry budget (1–10).
- Exponential retry delay in authenticated provider-result processing.
- Dead-letter quarantine after exhausted retry budget.
- Provider health and circuit-state registry.
- Adapter-secret protected provider receipt endpoint.
- Active lease and attempt-number validation.
- Provider operations dashboard, contract tests and CI.

## Dashboard
`/warranty/security-intelligence/providers`

## Adapter contract
A separately deployed server-side adapter must:
1. Claim due notifications through the protected dispatch workflow.
2. Resolve enabled provider configuration and recipient channel preferences.
3. Verify recipient contact information and consent.
4. Send through the selected provider with a stable idempotency key.
5. Verify signed provider webhooks or authenticated provider responses.
6. Submit a receipt with notification ID, attempt number, channel, provider and outcome.
7. Respect retry-after guidance, lease expiry, provider rate limits and circuit-breaker state.

## Important limitations
- No email, SMS, push or pager vendor SDK/API is integrated or configured.
- The dispatch endpoint only claims leased records; it does not send messages.
- Provider health registry is operational metadata; automatic circuit-breaker transitions, failover routing and health probes are not implemented.
- Retry scheduling is performed when an authenticated adapter reports a failure; no recurring scheduler or adapter worker is provisioned.
- Dead-letter replay UI and controlled replay API are not included.
- Provider receipt endpoint uses a shared adapter secret; production should use per-provider signing keys, webhook signature verification and key rotation.
- Ensure provider callbacks are idempotent. Attempt-number checks and unique attempt records reject common duplicate/stale receipts, but delivery and DB state updates are not one atomic transaction.
- No migration/test/CI execution, external provider delivery or production deployment is claimed.

## Validation
Run `npm run lint` and `npm run test:build010:notification-provider-adapters-retry-orchestration`. Stage abandoned leases, concurrent claim workers, duplicate provider callbacks, retry exhaustion, dead-letter quarantine, provider outage and recovery.
