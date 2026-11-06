# Build 009.93 — Warranty Security Compliance Reporting

## Delivered
- Six read-only compliance projections: executive KPIs, evidence integrity, access events, legal holds, retention jobs and chain-of-custody.
- Executive KPIs for scan health, flagged/pending evidence, active holds, retention backlog, granted/denied downloads and open security incidents.
- Evidence report includes evidence digest, scan state, collector and retention status.
- Access report exposes actor, action, reason, request correlation and timestamp.
- Legal-hold and retention reports expose lifecycle and blockers.
- Custody report exposes transfer participants, reason and digest continuity.
- RLS-enabled report-access audit table.
- Authenticated, role-scoped reports API with fixed resource allowlist, bounded pagination and no-store responses.
- Contract tests, CI workflow and operational documentation.

## Reports API
GET /api/warranty/security-compliance/reports?resource=summary|evidence|access|holds|retention|custody&limit=100&offset=0
Authorization: Bearer <Supabase access token>

CEO/privacy officer/manager can access the summary. Evidence, retention and custody are available to the listed operational roles. The access-event report is restricted to CEO and privacy officer. Every successful report read and authenticated denial/query failure is written to the report access audit table.

## Important boundaries
This build supplies reporting read models and an API, not a finished dashboard UI, PDF/XLSX export, compliance certification, regulatory filing or automatic CEO sign-off. Metrics reflect records in the security evidence/case schema only; they do not reconcile legacy warranty retention tables. No policy defaults are seeded, no worker schedules are activated, and no production migration replay or deployment is claimed.

The compliance views use invoker security and are service-role readable through the server API. Validate underlying table privileges and RLS in the target Supabase project. Access-report audit logging uses a service-role insert; verify operational retention and append-only controls before production.

## Validation
Run npm run lint and npm run test:build009:warranty-security-compliance-reporting. Integration tests should validate all role combinations, empty datasets, pagination bounds, audit failures, RLS isolation, and consistency between evidence, retention and custody data.
