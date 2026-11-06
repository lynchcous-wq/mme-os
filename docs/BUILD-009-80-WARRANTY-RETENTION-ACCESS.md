# Build 009.80 — Warranty Evidence Retention & Access Control

## Delivered schema foundation
- Effective-dated, versioned retention policies by evidence type.
- Evidence retention records linked to original evidence and policy version.
- Attributable legal holds and releases.
- Expiring, revocable evidence access grants by principal, role and permission.
- Append-only access and governance event history.
- Deletion queue with independent approval, lease fields and verified-deletion state.
- Time-bounded retention exceptions with separate approval.
- RLS enabled and browser-role access revoked on all seven tables.

## Governance rules
Retention duration must come from an approved policy with a documented legal basis; do not invent default durations. Retention records preserve the policy version used to calculate the due date. A legal hold or active approved retention exception blocks deletion. Releasing a hold requires an authorized privacy/legal role and a recorded reason.

Access must be checked server-side for every metadata view and file operation. Grants are principal-, evidence-, permission- and time-scoped. A signed URL, if later implemented, must be short-lived and issued only after the grant and claim ownership are rechecked. Every allow and deny decision must be audited without recording raw file contents, serial numbers or IMEIs.

Deletion is a two-phase process: eligibility review and independent approval, followed by a trusted storage worker that deletes the exact private object and verifies absence. The worker must recheck legal holds, exceptions and current retention status immediately before deletion. The database queue does not itself delete files. Evidence metadata and audit records remain subject to their own retention/legal requirements.

## Rollout boundary
Schema and governance contract only. No retention scheduler, policy seeding, legal workflow UI, access API, signed URL issuer, deletion worker, object removal or production migration replay is claimed.

## Validation
Run npm run lint and npm run test:build009:warranty-retention-access. PostgreSQL integration tests must cover policy effective dates, hold/release authorization, grant expiry/revocation, cross-customer isolation, dual-control deletion approval, hold race conditions, exception expiry and storage deletion verification.
