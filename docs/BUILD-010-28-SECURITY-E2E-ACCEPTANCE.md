# Build 010.28 — Security End-to-End Acceptance Testing

## Scope
This build adds an acceptance-contract suite for the Build 010.26 monitoring snapshots and Build 010.27 executive security command center.

## Acceptance coverage
- Monitoring and executive surfaces are both present.
- Session authentication and role authorization occur before privileged database REST calls.
- Executive write privileges are narrower than read privileges.
- Executive actions require a bounded rationale and are recorded with before/after state.
- Alert updates use row locking to avoid concurrent state races.
- Critical open alerts, dead-lettered events, and offline sources elevate overall status.
- Missing telemetry remains unknown/stale rather than being reported as healthy.
- The dashboard does not perform automatic adverse actions against customers or employees.

## Run
`npm run test:build010:security-acceptance`
`npm run test:build010:cross-system-security-monitoring`
`npm run test:build010:executive-security-command-center`
`npm run lint`
`npm run build`

## Environment-backed release checks (required before production)
1. Apply Build 010.26 and 010.27 migrations to a non-production Supabase project.
2. Verify prerequisite table names, alert columns, role claims, and service-role grants against the actual schema.
3. Test unauthenticated, expired-session, read-only-role, and executive-role requests.
4. Exercise acknowledge/resolve with valid and invalid rationales using a disposable test alert.
5. Confirm the audit row is written atomically with the alert state change.
6. Verify dead-letter, critical-alert, offline-source, and no-telemetry scenarios.
7. Run the full test, typecheck, and production build suites in CI.

## Limits
The contract tests do not connect to a live Supabase project or prove production provider delivery. No production credentials are used. No migration, merge, or deployment is performed by this build.
