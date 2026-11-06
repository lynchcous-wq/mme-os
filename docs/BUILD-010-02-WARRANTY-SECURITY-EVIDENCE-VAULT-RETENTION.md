# Build 010.02 — Warranty Security Evidence Vault & Retention

## Delivered
- Private Supabase Storage bucket `mme-warranty-security-evidence`.
- MIME allowlist and 50 MiB upload limit.
- Authenticated case-linked evidence upload endpoint.
- SHA-256 digest computed server-side.
- Evidence metadata registration and compensating object cleanup if metadata persistence fails.
- Short-lived (60-second) signed download URL.
- Server-side integrity verification against stored digest.
- Evidence access log for uploads, downloads and verification.
- Retention metadata and legal-hold records.
- Deletion request and independent approval/rejection workflow.
- CEO/privacy-officer authority for legal hold and deletion decisions.
- Evidence vault UI at `/warranty/security-evidence`.
- Contract tests and CI.

## API
- POST `/api/warranty/security-cases/:caseId/evidence` — multipart field `file`.
- GET `/api/warranty/security-evidence/:evidenceId` — creates a 60-second signed download.
- POST `/api/warranty/security-evidence/:evidenceId` with `{"action":"verify"}` — verifies SHA-256.
- POST `/api/warranty/security-evidence/:evidenceId/retention` — legal hold, release hold, request deletion, decide deletion.

## Important controls and limitations
- Evidence files are stored in a private bucket; service-role credentials stay server-side.
- Allowed MIME types: JPEG, PNG, WebP, PDF, plain text and JSON. Maximum 50 MiB.
- The application checks declared MIME type; it does not yet perform malware scanning or deep file-signature inspection.
- Legal holds block approval through the application workflow. Storage-level deletion execution is intentionally not implemented.
- Automated retention expiry, scheduled purge, deletion execution, legal-hold immutable enforcement at the database layer, and malware scanning remain future work.
- Audit log writes are attempted by API routes; production should fail closed if audit persistence is unavailable and should add immutable append-only DB controls.
- Existing case event route in earlier increment has an auth-header parser that should be corrected separately; this increment's new endpoints use the standard bearer-token parser.

## Validation and rollout
Run `npm run lint` and `npm run test:build010:warranty-security-evidence-vault-retention`. Apply migrations in order in staging. Confirm Storage is enabled, bucket is private, service-role secrets are server-only, allowed MIME settings are correct, and legal-hold/deletion policy is approved. Test upload, signed-link expiry, hash mismatch, role denial, audit logging and dual-control approval. No production migration, automated tests, deployment, malware scanning or deletion execution is claimed.
