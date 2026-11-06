# Build 009.91 — Warranty Security Evidence Ingestion & Integrity

## Delivered
- Private Supabase quarantine bucket with a 25 MiB object limit and MIME allowlist.
- Authenticated CEO/privacy-officer/manager multipart upload endpoint.
- Server-side file signature checks for PDF, JPEG, PNG, WebP, MP4 and text formats.
- SHA-256 digest calculated from uploaded bytes.
- Unique object paths scoped to case ID; no public URLs.
- Evidence registration with digest, size, content type, collector and timestamp.
- Unique scan-job queue and atomic batch claim using SKIP LOCKED.
- Protected scan worker that re-downloads the private object, verifies size and recomputes SHA-256 before sending it to the configured scanner.
- Scanner result lifecycle: clean, quarantined, failed; evidence remains in the private bucket.
- Failed scans are retried with bounded attempts/backoff.
- Contract tests, CI and operational documentation.

## Upload API
POST /api/warranty/security-evidence/upload
Authorization: Bearer <Supabase access token>
Content-Type: multipart/form-data
Fields: file, caseId, evidenceType, optional description.

Maximum file size: 25 MiB. Only the listed MIME types and matching file signatures are accepted.

## Scan worker
POST /api/internal/warranty-security-evidence-scan
Authorization: Bearer <MME_EVIDENCE_SCAN_WORKER_SECRET>

The scanner must be an HTTPS endpoint that accepts raw file bytes and X-Expected-SHA256, and returns JSON with a boolean clean plus optional scanner and code. Configure MME_EVIDENCE_SCANNER_URL, MME_EVIDENCE_SCANNER_TOKEN, and MME_EVIDENCE_SCAN_WORKER_SECRET as server-only deployment secrets.

## Critical rollout boundary
No malware scanner vendor or endpoint is provisioned by this repository change. Until a scanner is configured and validated, scan jobs will fail/retry and evidence remains pending_scan/scan_error in private quarantine. A clean scan result does not automatically promote an object to a public or general-access bucket. Do not permit investigators to download or use evidence until an authorization-checked retrieval flow confirms clean status.

The current signature check is a lightweight format gate, not a full parser or malware detector. File uploads require rate limiting, abuse monitoring, retention/legal-hold controls and an authenticated download path before production use. No production migration replay, storage setup verification, secrets configuration, scheduled worker, or deployment is claimed.

## Validation
Run npm run lint and npm run test:build009:warranty-security-evidence-ingestion-integrity. Integration tests must cover MIME spoofing, oversize files, failed DB registration cleanup, scanner outage, malicious result payloads, digest mismatch, duplicate claims, storage authorization and retry exhaustion.
