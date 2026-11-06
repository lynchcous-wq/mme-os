# Build 009.90 — Warranty Security Investigation & Case Management

## Delivered
- Investigation cases linked one-to-one to existing security incidents.
- Priority, due date, lead investigator, lifecycle and closure metadata.
- Investigator assignment with append-only case event.
- Typed investigation notes and decision/handoff/closure notes.
- Evidence metadata registry with SHA-256 digest, storage reference, collector and timestamp.
- Evidence custody transfer ledger with digest and prior-custodian validation.
- Append-only case event history.
- Service-role-only RPCs for case creation, assignment, notes, evidence metadata, custody transfer and status changes.
- Authenticated server API restricted to CEO, privacy officer and manager app_metadata roles.
- Contract tests and CI.

## API
POST /api/warranty/security-investigations
Authorization: Bearer <Supabase access token>

Actions: create, assign, note, evidence, custody, status. The API derives actor identity from the verified Supabase session; callers cannot supply their own actor ID.

## Evidence boundary
This build records evidence metadata and a storage bucket/path reference. It does not upload files, calculate the SHA-256 digest from file bytes, scan malware, enforce immutable object storage, or independently verify storage permissions. Those must be implemented in a controlled upload pipeline before operational evidence collection. Storage paths must not be exposed as public URLs.

## Security and workflow boundary
Tables are RLS-enabled and inaccessible to anon/authenticated roles; service-role RPCs are the controlled server path. Case closure requires a closure reason and is audited. A second-person closure approval, full investigator directory validation, legal hold/retention policy, exportable executive reports and rendered case UI remain future enhancements. No production migration replay or deployment is claimed.

## Validation
Run npm run lint and npm run test:build009:warranty-security-investigation-case-management. Integration tests must cover forged roles, session expiry, concurrent case creation, custody chain integrity, digest mismatch, storage authorization, closure workflow and audit immutability.
