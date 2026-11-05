# Build 004 — Protected Route Authorization Cutover Readiness

**Branch:** `integration/build004-identity-validation`  
**Reviewed baseline:** `24ade7890fd0e66e93b4ceceea6a390aa4d012e9`  
**Status:** Read-only route review. No route behavior, production authorization, or permission data was changed.

## Decision

Build 004's server-only authorization helper is available, but the inspected employee inventory-inspection routes still authorize through the legacy `mme_employee_authorize_inventory_action` RPC. The new helper is not yet integrated into these routes. Keep legacy authorization active; do not migrate grants or cut over protected routes until route-specific scope derivation and parity tests are complete.

## Route findings

| Route | Current authorization behavior | Required Build 004 migration work |
|---|---|---|
| `POST /api/employee/inventory/inspection` | Validates the bearer with Supabase Auth, derives actor from the Auth response, then the submit RPC applies the legacy permission check. Product/unit lookup is server-side. | After the unit lookup, derive product and location from the protected serialized-unit/product records, not the request body. Call the Build 004 helper with `inventory.inspection` / `submit` and that trusted scope. Preserve the database submit RPC's transactional validation and ensure it cannot bypass the new decision. |
| `POST /api/employee/inventory/inspection/resolve` | Authenticates the bearer; fetches the inspection row with service role; derives product/location from that row; calls legacy approve and resolve checks; then invokes resolution RPC. | Use the row's database-derived product/location scope with Build 004 for both `approve` and `resolve`. Retain pending-state and transactional resolution guards. Avoid trusting inspection IDs or scope fields as authorization by themselves. |
| `GET /api/employee/inventory/inspection/history` | Authenticates the bearer; queries only records inspected by that actor; then filters each row through legacy `view` authorization using stored product/location. | Use Build 004 `view` per row or a safe batch authorization RPC. Preserve actor-owned filtering, result limit, and private no-store response. Ensure a failure denies the affected row or whole request consistently. |
| `POST /api/employee/inventory/inspection/photos` | Authenticates bearer; fetches inspection record; enforces submitting-employee ownership and pending state; checks legacy `submit` permission using stored product/location; validates file signature and registers private evidence. | Replace the legacy permission decision with Build 004 `submit` using the fetched row's product/location. Preserve ownership, pending-state, MIME/signature, size, private storage, checksum, and rollback controls. |

## Important constraints

1. The request body, query parameters, path parameters, and client-supplied actor IDs are not trusted authorization scope.
2. Actor identity must come only from a successfully validated Supabase Auth response.
3. Product, location, department, and ownership context must come from service-role database reads or database functions that enforce row visibility and invariants.
4. The Build 004 helper is server-only and fail-closed. It returns 401 for missing/invalid sessions, 403 for denied decisions, and 503 for configuration/RPC failures.
5. Do not remove legacy checks until the same fixture matrix proves equivalent or intentionally stricter decisions for every affected route.
6. Route cutover must preserve transactional checks inside the write RPCs. A route-level authorization precheck alone is not a substitute for atomic database enforcement.
7. No service-role credential may be exposed to browser code.

## Validation gates before cutover

- Add route contract tests proving actor IDs are never accepted from client input.
- Add tests proving scope is read from protected database records, not request JSON.
- Exercise allow, deny, terminated employee, frozen access, CEO bypass, mismatched product/location, malformed/missing record, and authorization-service failure for each route.
- Verify RPC parameter names and SQL transaction guards match the route's requested resource/action.
- Run full fresh-database migration reset, pgTAP suite, TypeScript, production build, and Edge Function checks.
- Review route-by-route diff and retain rollback path. No production permission migration or live authorization switch without explicit approval.

## Current conclusion

Build 004 database parity tests are green on the reviewed baseline, but those tests do not prove that every protected application route uses Build 004. The inspected inventory-inspection routes remain on legacy authorization. Route integration and route-level security validation are the next workstream; permission migration remains blocked.
