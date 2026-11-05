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

- CI run: `41962499123` (push) — success.
- CI run: `41962505439` (pull request) — success.
- Validated commit: `22c6169796bbc759d31ad30bc63a21fd703dc34d`.
- Earlier corrected baseline runs `41962123496` and `41962118153` also passed on commit `93243f1f6c7a90783ee938f5d39daaef2ff59255`.
- TypeScript check and optimized Next.js production build: passed.
- Supabase Edge Function type-check: passed.
- Complete migration chain applied to a fresh local Supabase database: passed.
- Full pgTAP suite: **98 files, 1,025 tests; all successful**.
- Registered route runtime and contract tests: passed in CI. These execute route handlers with mocked Auth/database/storage responses; they are not live Supabase-backed request tests.
- npm dependency audit: `found 0 vulnerabilities` on this validated commit.
- The PostCSS override remains in `package.json`; the separate Next.js major-version upgrade was not applied.

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
