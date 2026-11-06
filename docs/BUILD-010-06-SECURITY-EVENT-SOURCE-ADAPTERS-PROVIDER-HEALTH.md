# Build 010.06 — Security Event Source Adapters & Provider Health

## Delivered
- Seven-source adapter gateway: POS, inventory, warranty, CRM, evidence, payments and returns.
- Per-source HMAC secret lookup and five-minute timestamp validation.
- Payload cap, event type allowlist and schema validation.
- Authenticated forwarding to the central signed ingestion endpoint.
- Source health registry and append-only check history.
- Authorized health API and provider health dashboard.
- Contract tests and CI workflow.

## Required server configuration
- `MME_SOURCE_SECRET_POS`
- `MME_SOURCE_SECRET_INVENTORY`
- `MME_SOURCE_SECRET_WARRANTY`
- `MME_SOURCE_SECRET_CRM`
- `MME_SOURCE_SECRET_EVIDENCE`
- `MME_SOURCE_SECRET_PAYMENTS`
- `MME_SOURCE_SECRET_RETURNS`
- `MME_SECURITY_EVENT_HMAC_SECRET` (shared secret used by central ingestion)
- `MME_INTERNAL_APP_URL`
- Existing Supabase URL, anon key and service role key.

## Gateway
POST `/api/internal/security-event-adapters`, signed using the source-specific HMAC secret. Signature input is `timestamp + "." + rawRequestBody`. Source header identifies the adapter. The gateway signs a normalized payload for central ingestion using the internal shared secret.

## Health
GET `/api/warranty/security-intelligence/source-health` with an authenticated session and approved operational role.

## Limitations / rollout gates
- These are gateway adapters, not completed native publishers inside each department. Each source must implement event publishing and secure secret provisioning.
- This first version uses a single shared internal HMAC secret between gateway and central ingestion; use a private network and rotate it. A per-source credential registry and key rotation workflow remain future work.
- Health reflects observed adapter delivery attempts; it is not a synthetic end-to-end check. Heartbeats, credential checks and provider uptime polling remain to be built.
- Provider failover is not implemented. Automatic failover without idempotency and source-of-truth reconciliation would be unsafe.
- The health counter fields are schema placeholders and require atomic increment logic before reporting trustworthy totals.
- The gateway currently forwards only the normalized allowed event fields. Validate optional case/evidence UUIDs in staging.
- No live publishers, secrets, deployment, runtime test or production health verification is claimed.

## Validation
Run `npm run lint` and `npm run test:build010:security-event-source-adapters-provider-health`. Stage each source independently; verify bad signatures, replayed timestamps, duplicate event IDs, downstream outage behavior, health-state transitions and secret rotation.
