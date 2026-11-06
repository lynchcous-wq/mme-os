# Build 010.67 — Enterprise Communications & Contact Center

## Implemented
- Business phone-number register with E.164 format validation.
- Employee extension register.
- Call queue configuration register.
- Call log and event timeline tables.
- Recording and transcript metadata registers with consent state and retention metadata.
- Channel/purpose-specific customer consent ledger.
- Message outbox and server-side marketing-consent suppression RPC.
- Authenticated staff API, dashboard, RLS, service-role-only table access and acceptance tests.

## Production blockers
- No telephony carrier integration, number provisioning, inbound/outbound calling, extension registration with provider, routing, queue membership administration, transfer, hold, voicemail or callback provider workflow.
- API writes call event then updates call state in separate operations; implement transactional event RPC and legal state machine, concurrency protection and immutable audit.
- Call-event action currently treats event registration as a logged event, not a provider-signed webhook. Add provider webhook signature verification, idempotency and replay protection.
- Message outbox only queues. No worker, provider dispatch, delivery receipts, retries, bounce handling or suppression webhook integration.
- Service-purpose messages do not yet enforce channel permission, customer service relationship, opt-out and quiet-hour policy; marketing checks current granted row but must also evaluate latest event precedence and explicit suppression/withdrawal atomically.
- Recording metadata does not capture audio. Recording consent requirements vary by jurisdiction and call participants; implement state/jurisdiction policy, notice, explicit consent proof, retention/deletion, access logging and restricted playback before activation.
- No call recording storage, transcript engine, live call monitoring, employee performance capture, transcription redaction or legal hold.
- Role authorization is broad; implement store, department, employee, queue and record-level permissions. Verify employee IDs and customer associations.
- CRM identity screen-pop, customer purchase context, caller ID provider lookup and customer portal messaging remain unintegrated.
- Add PII encryption, rate limits, outbox idempotency, pagination, retention jobs, security review and integration tests.

## Validation
Run `npm run test:build010:communications`, CRM/identity/security suites, `npm run lint`, and `npm run build`. Tests not executed, migration not applied, not merged or production deployed.
