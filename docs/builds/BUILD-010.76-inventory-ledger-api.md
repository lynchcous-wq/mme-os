# Build 010.76 — Inventory Ledger API & Transaction Processing

Status: implementation contract committed on an isolated feature branch. No production runtime code, schema migration, or deployment is claimed by this document.

## Repository audit findings

Audited the current default-branch repository structure and relevant POS transaction files before defining this build.

- The app is Next.js 15 with TypeScript; package scripts include `build` and `lint` (TypeScript no-emit).
- POS transaction creation is routed through `app/api/pos/transactions/route.ts`.
- POS requests use `authenticatePosRequest` from `lib/pos/authenticated-server.ts`, which verifies the Supabase Auth bearer token, resolves the MME person identity, and keeps the service-role key server-side.
- The existing POS create flow calls the database RPC `mme_pos_create_transaction` and uses an Idempotency-Key header.
- The current default-branch migration inventory exposed only the Build 010 warranty/security dashboard migration. The existing POS SQL migration and inventory schema were not present in the audited tree snapshot. Do not infer their table or function definitions.
- The warehouse UI references `/api/warehouse`; that API route was not present in the audited default-branch tree. Treat it as a separate unresolved integration dependency, not as a working endpoint.

## API contract

Implement inventory ledger operations as server-authenticated routes using the existing POS authentication pattern, but do not assume every POS employee is authorized for every inventory operation. Add a server-side permission check using the canonical MME role/permission source after its schema is audited.

Proposed endpoints:

- `POST /api/inventory/movements`: create or replay an idempotent stock movement.
- `GET /api/inventory/balances`: return authorized location/item balances.
- `POST /api/inventory/transfers`: create or dispatch a transfer.
- `POST /api/inventory/transfers/:id/receive`: receive dispatched quantities.
- `POST /api/inventory/counts`: open or submit a physical count.
- `POST /api/inventory/counts/:id/approve`: approve and post count variance.
- `GET /api/inventory/exceptions`: list authorized unresolved posting exceptions.

## Movement request

Require an `Idempotency-Key` header (8–128 characters). Validate a strict JSON schema; reject unknown keys. The server supplies actor identity from the verified session and never trusts a client-supplied actor/person ID.

Required business fields: `item_id`, `location_id`, `movement_type`, `quantity_delta`, `source_type`, and `source_reference`. Optional fields include `serial_id`, `reason_code`, and a non-sensitive note. Quantities must be finite, non-zero, and within configured bounds. Movement types must be an explicit allowlist; arbitrary client-defined types are rejected.

The database RPC must atomically:
1. Verify the actor's active status and permission for the target store/location and operation.
2. Validate source eligibility and serialized-device custody if applicable.
3. Resolve an existing idempotency key and return its original result if the payload matches; reject key reuse with a different payload.
4. Insert the immutable movement and update/derive the balance in one transaction.
5. Record an audit event and return the canonical movement/balance result.

The service-role credential must never be returned to the client or logged. Do not return complete IMEI/serial values in list or dashboard responses.

## Transaction and error semantics

- 201: newly posted movement.
- 200: idempotent replay of the same request.
- 400: malformed or invalid request.
- 401: missing/invalid session.
- 403: authenticated actor lacks the operation/location permission.
- 409: source is ineligible, stock constraint fails, or idempotency key was reused with a different payload.
- 503: required database or auth dependency is unavailable; do not imply the operation succeeded.

A response timeout after a successful commit must be recoverable by retrying with the same idempotency key.

## Implementation dependencies and blockers

Before writing the migration/API implementation, inspect and reuse the canonical:
- store/location table and key,
- product/inventory item table and key,
- identity/role/permission tables and permission evaluation function,
- existing POS order reservation and sale-completion functions,
- warehouse fulfillment source tables and status transitions,
- serial/IMEI table and masking policy,
- inventory cost/valuation source.

No parallel product, identity, location, role, or cost source may be introduced. The migration must be additive and include explicit RLS, grants, constraints, indexes, and rollback notes.

## Required tests

- Unauthenticated request is rejected.
- Customer session is rejected from employee-only operations.
- Employee without inventory permission is denied server-side.
- Authorized employee cannot access a different store/location outside their scope.
- New movement commits once; same-key same-payload retry replays.
- Same key with altered payload is rejected.
- Concurrent same-key requests produce one movement.
- Database failure cannot leave a partial balance update.
- Serialized device requires valid custody and unique active identity.
- Movement list masks serial/IMEI.
- Build, TypeScript lint, and existing POS contract tests pass.
- Existing customer/employee sign-in, product catalog, POS, and warehouse regression tests remain green.

## Release gates

This contract does not authorize production deployment. Runtime API, database migration, test execution, and environment verification are separate required deliverables. Do not mark Build 010.76 complete until those gates pass against the actual Supabase project and Vercel deployment.
