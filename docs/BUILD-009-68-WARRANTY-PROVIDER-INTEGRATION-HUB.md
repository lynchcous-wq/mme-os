# Build 009.68 — Warranty Provider Integration Hub

## Scope
Adds a provider registry, sandbox/production connection metadata, provider programs, retry-safe claim submission outbox, webhook inbox, SLA event ledger and settlement reconciliation. This is an integration foundation; provider-specific adapters and live credentials must be configured separately.

## Credentials and network security
Only a secret-manager reference is stored. API keys, OAuth refresh tokens, passwords and signing secrets must never be stored in Postgres, source control, logs or webhook payloads. Provider adapters must use TLS, strict outbound host allowlists, DNS/IP validation, timeouts, bounded response sizes, schema validation and secret rotation. Sandbox and production credentials remain isolated.

## Eligibility and claim submission
Eligibility checks and claim submissions are queued through an idempotent outbox. A worker must verify active provider, active program, warranty coverage, serialized-unit identity, customer authorization, required evidence and claim amount before dispatch. Provider-specific field mapping belongs in versioned adapters. Retry only transient errors; dead-letter permanent or exhausted failures. Do not claim that an outbox row means a provider received a claim.

## Webhooks
Verify provider signatures and timestamp/replay windows before marking an event trusted or processing it. The webhook inbox enforces unique provider event IDs. Persist minimal sanitized payloads, reject unknown event types, and make processing idempotent. The database signature flag is metadata; the trusted API gateway/adapter must perform cryptographic verification.

## Reconciliation and SLA
Settlement records preserve expected and received amounts, currency, source reference and variance. Provider claim approval is not cash received; only bank/settlement evidence can confirm receipt. Finance approval and matching to Build 009.66 financial entries are required before posting actual provider recovery. SLA events support response-time and availability reporting.

## Security and governance
RLS on all tables; no browser table access. Service-role RPCs are callable only by authenticated backend routes with provider-admin, warranty-operations and finance permissions as appropriate. Require dual approval for production connection activation, endpoint changes and settlement approval. Validate endpoint URLs against an explicit provider allowlist to prevent SSRF.

## Validation
Run npm run lint, npm run test:build009:warranty-provider-hub and existing warranty-repair, warranty-financial, warranty-risk and financial-provider-sync suites. Integration tests must cover idempotent submissions, sandbox/production isolation, secret redaction, webhook signature/replay rejection, provider mismatch, transient retries, dead-letter behavior, settlement variance and currency matching.

## Rollout boundary
Draft implementation only. No live provider adapter, provider credentials, webhook endpoint, eligibility network call, automated claim submission, bank settlement import, production migration replay or deployment is claimed.
