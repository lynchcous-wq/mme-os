# Build 010.03 — Warranty Security Intelligence & Threat Detection

## Delivered
- Signal registry for serial mismatches, duplicate serials, claim velocity, repeat claim patterns, evidence integrity mismatches, unusual evidence access, policy override patterns and device identity conflicts.
- Subject identifiers normalized and SHA-256 fingerprinted server-side before persistence.
- Versioned deterministic scoring with bounded 0–100 output and per-signal factor explanation.
- 30-day assessment window, signal count and confidence label.
- Risk bands: low, guarded, elevated, high and critical.
- Assessment history and case/evidence relationship schema.
- Separate human-review record with rationale and append-only update/delete guard.
- Authenticated signal assessment and history API.
- Human review API.
- Workspace at `/warranty/security-intelligence`.
- Contract tests.

## API
- POST `/api/warranty/security-intelligence` — accepts subjectKey and 1–50 typed signals.
- GET `/api/warranty/security-intelligence?subject=<sha256>` — retrieves a fingerprint's signals and assessment history.
- POST `/api/warranty/security-intelligence/:assessmentId/review` — records outcome and rationale.

## Scoring governance
The initial ruleset is `mme-warranty-risk-rules-v1.0`. Signal weights are deterministic, repeated signals are discounted, the score is capped at 100 and every assessment requires review. Confidence is a transparent volume heuristic, not a calibrated probability. The score is an investigation-prioritization aid, not proof of fraud.

No automatic warranty denial, refund denial, customer restriction, employee discipline or account suspension is allowed. Review outcomes are recorded separately from the assessment.

## Important limitations
- The current API accepts typed signals from an authorized application caller. It does not yet ingest and independently validate live signals from POS, CRM, inventory, warranty or evidence events.
- Case correlation schema is present; automated correlation/link population remains a follow-on.
- No machine-learning model, predictive accuracy claim or trained AI is included.
- No automatic customer or employee adverse action.
- The review route persists the review before updating the assessment summary; if the second operation fails, the review record remains authoritative and requires reconciliation.
- Role mapping and access to sensitive subject-level intelligence must be validated against actual Supabase app_metadata claims.

## Validation and rollout
Run `npm run lint` and `npm run test:build010:warranty-security-intelligence-threat-detection`. Apply migration in staging, test RLS, role denials, fingerprint normalization, scoring boundaries, duplicate signal idempotency, history access and review append-only controls. No production migration, automated test execution, deployment, external event ingestion or model training is claimed.
