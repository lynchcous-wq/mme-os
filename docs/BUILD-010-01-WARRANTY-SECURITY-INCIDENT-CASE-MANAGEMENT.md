# Build 010.01 — Warranty Security Incident Case Management

## Delivered
- Unique warranty security case numbers.
- Case records linked to originating security alerts.
- Automatic case creation when a new warranty security alert is inserted.
- Severity, priority, assignment and due-date fields.
- Lifecycle statuses: open, triage, investigating, pending action, pending approval, resolved, closed and reopened.
- Append-only case event history for case creation and material updates.
- Internal and executive investigation notes.
- Evidence metadata registry with SHA-256 digest, storage object key and 50 MB metadata size limit.
- Corrective action records with owner, due date and completion state.
- Authenticated case list/create API and case event API.
- Case workspace at `/warranty/security-cases`.
- Contract tests.

## API
- GET/POST `/api/warranty/security-cases`
- POST `/api/warranty/security-cases/:caseId/events`
- Supported event types: note, assign, status, action.
- Approved app_metadata roles: ceo, privacy_officer, manager, warranty_investigator.

## Evidence security boundary
This increment registers evidence metadata only. It does not upload files, create a private storage bucket, issue signed URLs, scan malware or enforce retention/deletion. Configure private storage and evidence access policy before collecting actual evidence. Do not place sensitive evidence in public buckets.

## Operational boundaries
Automatic alert-to-case creation is performed by a database trigger. Manual creation may link an alert using alertId. The event API records notes, assignments, statuses and corrective actions; database-level case audit triggers record case creation and material case updates. Verify trigger behavior and actor attribution in staging. System-created alert cases use a zero UUID system actor marker.

## Validation and rollout
Run `npm run lint` and `npm run test:build010:warranty-security-incident-case-management`. Apply migrations in order in staging, verify RLS, case sequence, alert trigger, role claims, case lifecycle and evidence policy. No production migration replay, tests, deployment or live evidence storage is claimed.
