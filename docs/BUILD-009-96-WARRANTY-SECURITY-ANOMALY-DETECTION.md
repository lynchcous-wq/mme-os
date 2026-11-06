# Build 009.96 — Warranty Security Anomaly Detection

## Delivered
- SQL detection function for repeated denied downloads (5+ per actor/case per 30 minutes).
- High-volume successful download detector (20+ per actor/case per configurable 5–10,080-minute window).
- Evidence integrity signals for quarantined, rejected and scan-error ingestion states.
- Overdue/failed retention-job signals, excluding evidence under active legal hold.
- Deterministic detection fingerprints and unique deduplication for unreviewed signals.
- Authenticated signal feed and CEO/privacy-officer-only detection trigger APIs.
- Bounded inputs, no-store responses, contract tests and CI workflow.

## Endpoints
GET /api/warranty/security-anomalies?limit=100
POST /api/warranty/security-anomalies/detect
Body: { "windowMinutes": 60 }

The detector uses existing evidence access events, case evidence and retention-job records. It creates signals in the Build 009.95 risk ledger; reviewers can process them using the existing risk-review API.

## Safety and scope
Anomaly thresholds are initial operational heuristics, not calibrated machine-learning models. A high-volume download may be legitimate bulk work. Denied attempts do not establish malicious intent. No employee is labeled guilty, no disciplinary action or account restriction is triggered, and no evidence is deleted. Active legal holds suppress retention-overdue signals.

This increment does not yet detect cross-case repeat patterns, changing employee baselines, device/IP anomalies, modification history or claim fraud. It does not provide a scheduled worker; an authorized CEO/privacy officer must invoke the detector endpoint. Validate role metadata and data provenance in staging.

## Validation
Run `node --test tests/build009-warranty-security-anomaly-detection.test.mjs` and `npm run lint`. Integration-test threshold boundaries, deduplication across repeated runs, legal hold exclusion, role checks, service-role grants and high-volume datasets.
