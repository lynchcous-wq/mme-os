# Build 009.70 — Warranty Customer Portal
Adds backend data contracts for customer warranty access, communication preferences, customer-safe claim status summaries, warranty service requests, private document metadata and activity history.

Customer identity must be resolved server-side from the authenticated session; never trust a customer ID supplied by the browser. Every read and mutation must enforce ownership at the API/database boundary. Expose customer-safe status summaries only, never internal fraud scores, provider credentials, staff notes or raw webhook payloads.

Documents belong in private object storage. Enforce MIME allowlists, 20 MiB limit, checksum verification, malware scanning, short-lived signed URLs, access logging and retention policy. A pending or failed scan must not be downloadable or passed to staff workflows as trusted evidence.

Communication preferences must honor transactional/legal requirements separately from optional marketing consent. Requests are submissions, not proof that a claim is accepted or a repair authorized. Provide accessible status, clear next steps and support escalation.

RLS is enabled on all tables and browser grants are revoked; authenticated API routes/service role must implement ownership checks and least privilege. No customer UI, live storage bucket policy, upload endpoint, authentication binding, production migration replay or deployment is claimed.

Validation: npm run lint; npm run test:build009:warranty-portal; PostgreSQL integration tests for cross-customer access denial, signed URL expiry, malware scan gating, consent and idempotency.
