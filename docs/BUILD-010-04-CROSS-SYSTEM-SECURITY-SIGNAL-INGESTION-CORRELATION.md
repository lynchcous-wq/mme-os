# Build 010.04 — Cross-System Security Signal Ingestion & Correlation

## Delivered
- Private event inbox with unique event IDs, payload digest, source system, subject fingerprint, case/evidence references and processing state.
- Signed HMAC-SHA256 event ingestion endpoint with five-minute timestamp tolerance and constant-time signature comparison.
- Strict source-system allowlist, typed event allowlist, JSON validation and 32 KiB payload cap.
- Subject fingerprinting and payload SHA-256 digesting.
- Idempotent inbox and signal insertion keys.
- 30-day same-subject correlation across distinct systems.
- Correlation confidence labels and explanatory rule metadata.
- Authenticated correlation history endpoint.
- Cross-system dashboard at `/warranty/security-intelligence/cross-system`.
- Contract tests and CI workflow.

## API
- POST `/api/warranty/security-intelligence/ingest` — signed source event.
- GET `/api/warranty/security-intelligence/correlations?subject=<sha256>` — authorized correlation history.

### Event signing
Headers: `X-MME-Source`, `X-MME-Timestamp` (Unix seconds or milliseconds), `X-MME-Signature` (hex HMAC-SHA256).
Signature input: `timestamp + "." + rawRequestBody`.
Secret: server-only `MME_SECURITY_EVENT_HMAC_SECRET`.
Payload: `eventId`, `eventType`, `subjectKey`, optional `caseId`, `evidenceId`, `occurrenceCount`, `observedAt`.

Allowed sources: POS, inventory, warranty, CRM, evidence, payments, returns.
Allowed event types map to the existing intelligence signal taxonomy.

## Correlation safeguards
Correlations are generated only when the same normalized subject fingerprint appears in at least two distinct source systems. Confidence labels are rule-based volume indicators, not calibrated probabilities. Correlations are investigation leads, not findings of wrongdoing. No automated warranty denial, refund denial, customer restriction or employee discipline is permitted.

## Limitations and rollout
- Source adapters, secret provisioning/rotation, retry queue, dead-letter handling, event delivery monitoring and end-to-end live integrations are not included.
- The endpoint uses a shared HMAC secret; production should use per-source credentials and rotation.
- Event timestamps are currently validated for signature freshness; business event-time validation and ordering controls need further hardening.
- The event inbox and correlations are service-role only; validate RLS and role claims in staging.
- Correlation rules are simple same-subject matching, not AI or predictive fraud detection.
- No production migration, automated tests, deployment or live source integration is claimed.

Run `npm run lint` and `npm run test:build010:cross-system-security-signal-ingestion-correlation`, then validate signatures, replay rejection, duplicate delivery, source isolation, event ordering and correlation behavior in staging.
