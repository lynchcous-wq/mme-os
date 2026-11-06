# Build 009.89 — Warranty Security Executive Cockpit

## Delivered
- Executive KPI read model for open, critical, high, recent and resolved incidents.
- Executive incident list with owner, lifecycle timestamps, timeline count and acknowledgement count.
- Incident activity/timeline feed.
- Security event feed with category, severity, resource, actor role and occurrence counts.
- Role-gated server API for CEO, privacy officer and manager.
- Fixed read-model allowlist; no caller-selected table names.
- Bounded result size, request IDs and no-store response headers.
- Authenticated incident acknowledgement action using the verified Supabase user ID.
- Contract tests and CI.

## Route contract
GET /api/warranty/security-cockpit?resource=kpis|incidents|activity|events
Authorization: Bearer <Supabase access token>

POST /api/warranty/security-cockpit
Authorization: Bearer <Supabase access token>
JSON: {"action":"acknowledge","incidentId":"<uuid>","note":"<optional note, max 500 chars>"}

## Access and privacy
Only app_metadata role claims CEO, privacy_officer or manager are accepted. Role assignment must be performed by a trusted administrative process; user-editable metadata is not trusted. Database service credentials remain server-side. Security event feed intentionally omits raw IP digests and actor IDs. Do not expose this API through public browser database access.

## Implementation boundary
This build adds backend executive read models and the protected API contract. It does not add a rendered cockpit page, charts, heatmap, export files, privacy officer-specific layout, live subscriptions, or deployment. Those require integration with the app's existing authenticated navigation/session provider and UI conventions. No production migration replay or role assignment is claimed.

## Validation
Run npm run lint and npm run test:build009:warranty-security-executive-cockpit. Integration tests must cover session expiry, forged roles, manager/CEO/privacy access, acknowledgement actor integrity, RLS, bounded reads and sensitive-field omission.
