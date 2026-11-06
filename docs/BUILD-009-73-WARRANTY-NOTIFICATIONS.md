# Build 009.73 — Warranty Notifications & Communications Engine

Adds approved versioned templates, purpose/channel-specific consent evidence, channel preferences with timezone-aware quiet hours, delivery attempts, suppression records and provider callback inbox.

The existing lifecycle notification outbox remains the source queue. A worker must claim messages with bounded leases, verify customer contact data, resolve the approved template version, check latest consent and suppression, apply quiet hours and idempotency, then submit to an enabled provider. Provider acceptance is not proof of delivery; only verified provider callbacks may advance delivery state.

Transactional/service notices and marketing renewal offers are distinct purposes. Marketing requires explicit current consent. Revocation and channel opt-out must suppress pending sends. Do not bypass legal or account-security notices; route those through the approved policy channel and audit.

Retries apply only to transient failures with exponential backoff, jitter, attempt caps and dead-letter review. Permanent failures, invalid destinations, complaints and opt-outs are not retried. Callback signatures must be verified before processing; store payload digests rather than unrestricted raw sensitive payloads.

All new tables have RLS and browser grants revoked. Provider credentials stay in server-side secrets. Do not log message bodies, full phone numbers or email addresses. Template variables must be allowlisted and escaped.

Validation: npm run lint; npm run test:build009:warranty-notifications; PostgreSQL integration tests for consent precedence, opt-out suppression, quiet-hour timezone/DST edges, callback signature verification, duplicate callbacks, retries and dead-letter behavior.

Rollout boundary: schema and contract tests only. No SMS/email provider credentials, worker deployment, actual message delivery, production migration replay or customer UI is claimed.
