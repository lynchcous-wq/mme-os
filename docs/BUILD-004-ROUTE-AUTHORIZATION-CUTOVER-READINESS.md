# Build 004 — Protected Route Authorization Cutover Readiness

**Branch:** `integration/build004-identity-validation`  
**Status:** Route-level Build 004 dual authorization is implemented for the four inventory-inspection endpoints below. The latest CI run passed all registered checks. The runtime route suites use mocked Supabase/Auth responses and are not equivalent to a live Supabase-backed authorization integration test. Legacy checks remain active; no permission migration or production cutover has occurred.

## Route implementation status

| Route | Build 004 check | Trusted scope / identity | Legacy and transactional controls |
|---|---|---|---|
| `POST /api/employee/inventory/inspection` | `inventory.inspection / submit` | Product and location from the serialized-unit database lookup; Auth subject maps to `mme_person_identities.id`. | Legacy atomic submit RPC remains; actor Auth UUID and person identity are passed separately. |
| `POST /api/employee/inventory/inspection/resolve` | Both `approve` and `resolve` | Product and location from the protected inspection row; Auth subject maps to person identity. | Legacy approve/resolve checks and final resolution RPC remain. |
| `GET /api/employee/inventory/inspection/history` | `inventory.inspection / view` per returned row | Auth subject maps to person identity; query is constrained to the mapped inspector identity; product/location come from each database row. | Legacy view check remains. Build 004 denial filters the row; helper/service errors fail closed with their 401/503 status. |
| `POST /api/employee/inventory/inspection/photos` | `inventory.inspection / submit` | Product/location from protected inspection row; Auth subject maps to person identity; uploader must be the mapped submitting identity. | Legacy submit check remains. Private storage, file signature/size checks, metadata registration, and rollback behavior remain. |

## Contract tests registered in CI

- `test:build004-inspection-submit`
- `test:build004-inspection-resolve`
- `test:build004-inspection-history-photos`

The route contract tests verify Build 004 helper usage, database-derived scope, distinct Auth/person identity mapping, retention of legacy checks, and selected evidence safeguards. They are source-contract tests, not live authorization integration tests.

## CI validation record

- CI run: `41960019841` (push) — success.
- CI run: `41960024834` (pull request) — success.
- Validated commit: `ebd1278c75b6878938de4fb45acd2426a95eaaaf`.
- TypeScript check and optimized Next.js production build: passed.
- Supabase Edge Function type-check: passed.
- Complete migration chain applied to a fresh local Supabase database: passed.
- Full pgTAP database test step: passed.
- Build 004 inspection contract tests: 17 assertions/tests passed across the three contract suites.
- Build 004 inspection runtime handler tests: 21 tests passed across submission (6), resolution (4), history (5), and photo evidence (6).
- Identity authorization helper tests: 11 tests passed across contract and runtime suites.
- Before the PostCSS override, CI reported two npm audit advisories: direct `next` (moderate) and transitive `postcss` (high, affected through 8.5.22). The compatible `postcss` override is committed in `package.json`; on commit `abeaf37cb1d5fd5eefcedfbb6bc07671fc11d8de`, CI dependency installation reported `found 0 vulnerabilities`. The full Supabase migration/pgTAP job was still running when this record was updated. The `next` major-version upgrade was not applied.

## Remaining validation gates

1. Add or run live Supabase-backed request-level tests for allow, deny, terminated employee, frozen access, CEO bypass, mismatched scope, malformed/missing record, and authorization-service outage for each route. Current route runtime tests mock Auth and database HTTP responses.
2. Confirm database RPC identity parameter contracts and transactional invariants for each route under the local Supabase test environment.
3. Keep monitoring dependency advisories and assess the separate Next.js major-version upgrade on its own compatibility branch; do not run force upgrades.
4. Review the combined diff and rollback plan.
5. Only then consider permission migration or production cutover, requiring explicit approval.

## Security and rollout decision

- Request body, query, and path values are not trusted authorization scope.
- Actor identity originates from a validated Supabase Auth response.
- Build 004 person identity is resolved separately; Auth UUID is not assumed to be the person-identity primary key.
- Legacy checks and transactional RPC safeguards remain active as defense in depth.
- Service-role credentials remain server-side.
- A route-level authorization check does not replace atomic database enforcement.
- No production permissions, live authorization switch, or deployment was changed by this route integration.

**Current decision:** The four route integrations and registered CI checks are green on the validated commit. Additional live Supabase-backed behavioral/security coverage and dependency-advisory review remain. Keep permission migration and production cutover blocked.
