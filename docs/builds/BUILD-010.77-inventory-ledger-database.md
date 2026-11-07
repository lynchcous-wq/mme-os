# Build 010.77 — Inventory Ledger Database & Atomic Posting Engine

Status: database implementation contract committed on an isolated feature branch. No SQL migration has been applied and no live database objects are claimed.

## Audit result and implementation boundary

Build 008 defines the inventory domain and explicitly says it is a specification, not an implemented database. Build 010.75 requires inspection of canonical inventory, location, identity, serial, POS, warehouse and cost records before runtime changes. Build 010.76 establishes the API contract.

The repository snapshot inspected for this build contains a Supabase migration directory with the Build 010 warranty/security dashboard migration, but does not expose the canonical inventory schema or the existing POS transaction-creation SQL function. The application does contain a POS API that calls `mme_pos_create_transaction`, and its server helper resolves authenticated Supabase users to MME person identities. Those are integration clues, not sufficient evidence to safely create foreign keys, triggers, RLS policies or inventory posting functions.

Therefore this build records the database invariants and migration design. It deliberately does not invent table names, primary keys, role policy semantics, or a competing stock/cost source.

## Database invariants

1. **One authoritative movement history.** Every committed stock change has one immutable movement record with stable movement ID, canonical item and location references, movement type, signed quantity, source reference, actor/service identity, timestamp, correlation ID and idempotency identity.
2. **Append-only correction model.** Posted movements cannot be updated or deleted by application roles. Corrections are compensating movements with reason and approval references.
3. **Atomic balance semantics.** Movement creation, idempotency reservation, balance update or balance projection, source-state transition and audit event commit or roll back as one database transaction.
4. **Idempotency.** Enforce a unique key within a documented tenant/store/operation scope. Store a canonical request fingerprint and result reference. Same key and same payload replays the original result; same key with a different payload returns a conflict.
5. **Concurrency.** Lock the relevant balance/source rows or use an equivalent serializable/atomic strategy. Concurrent attempts cannot oversell, double-deduct, double-receive or double-post.
6. **Distinct quantities.** Preserve on-hand, reserved, available-to-promise and in-transit as distinct semantics. Do not treat a pick scan as fulfillment or decrement stock before the authorized fulfillment commit.
7. **Serialized custody.** Serialized units have validated unique active identity and a controlled state/location transition. Restricted serial/IMEI values are masked from routine responses and excluded from logs.
8. **Scope and authorization.** Database policies and security-definer RPCs validate the canonical active identity, permission, and store/location scope. Service-role access is limited to server-side code; no service credential is exposed to browser clients.
9. **Source authority.** POS/order, warehouse fulfillment, receiving, transfers, returns and counts remain their own source workflows. Inventory posts only eligible, authorized source events.
10. **Durable failure.** An operation that cannot post must not leave a partial balance change. Durable exceptions are written only where the transaction design can guarantee truthful status and recovery.
11. **Valuation boundary.** Reference the existing approved acquisition/COGS and accounting valuation policy. Do not create a second cost basis or derive inventory value from unapproved estimates.

## Logical data capabilities

After canonical schema discovery, the additive migration may add only missing capabilities:

- movement journal with immutable posting metadata;
- idempotency registry with request fingerprint and replay result;
- balance projection or materialized balance view, only if no canonical equivalent exists;
- source posting/outbox records for reliable cross-module delivery;
- posting exception records with retry/resolve lifecycle;
- count variance approval references if not already owned by the count workflow;
- transfer in-transit accounting only if no existing authoritative transfer model exists.

All foreign keys must point to existing canonical product/item, location/store, identity and source records. Do not create duplicate product, employee, customer, location, serial, order, or cost master tables.

## Required RPC transaction shape

The eventual posting RPC must execute in one database transaction:

1. Validate required arguments and reject unknown or invalid movement/source types.
2. Resolve the actor through the canonical identity mapping and verify active status.
3. Verify action permission and store/location scope using the authoritative permission model.
4. Resolve the idempotency key under a unique constraint. On conflict, compare request fingerprint and replay or reject.
5. Lock source and affected balance/unit records in a deterministic order to avoid race conditions and reduce deadlocks.
6. Verify source workflow eligibility and sufficient stock/reservation conditions.
7. Validate serialized unit identity and custody when the product tracking policy requires it.
8. Insert the immutable movement and update the balance projection atomically, or update the existing canonical stock record if that is the approved system of record.
9. Record audit metadata and an outbox/source-posting event in the same transaction.
10. Persist the replay result and return a canonical movement ID and balance snapshot/version.

The database must not perform network calls to payment providers, shipping providers, or other external services inside this transaction. Use an outbox/worker pattern for external delivery.

## Security and database controls

- Enable RLS on newly introduced tables.
- Revoke default privileges from `public`, `anon`, and `authenticated` unless a narrowly scoped policy explicitly requires access.
- Grant only required table/function privileges to the correct server role.
- Pin `search_path` on security-definer functions and schema-qualify referenced objects.
- Validate function execution rights and ensure callers cannot spoof actor identity.
- Prevent update/delete of posted journal rows through grants and database enforcement.
- Add indexes for canonical item/location/time, source references, idempotency lookup, unresolved exceptions and outbox delivery state.
- Add check constraints for non-zero finite quantity, supported states, valid timestamps and consistent source metadata.
- Avoid storing raw authorization tokens, service credentials, full IMEI/serial values in audit payloads, or payment card data.

## Migration sequencing and rollout

1. Inventory all existing Supabase migrations and live database objects; reconcile migration history with the target project before applying anything.
2. Identify canonical table/function names and exact column types from migrations and live schema introspection.
3. Map each existing stock write path: receiving, POS reservation/sale completion, warehouse fulfillment, transfer, count, return, manual adjustment and import.
4. Select one authoritative posting path and define compatibility adapters for existing callers.
5. Add only missing tables, constraints, indexes, functions, policies and grants in a reversible additive migration.
6. Backfill only from verified source records, preserving provenance and reconciling totals before cutover.
7. Run in shadow/observe mode first; compare ledger-derived quantities with existing balances without changing production writes.
8. Enable posting per source only after reconciliation and regression gates pass.
9. Monitor duplicate/rejected commands, ledger/balance drift, posting lag, deadlocks and unresolved exceptions.
10. Keep rollback instructions that disable new callers safely without deleting committed ledger history.

## Acceptance tests

- Same idempotency key and same payload returns one movement/result.
- Same key and different payload is rejected.
- Parallel same-key requests produce exactly one committed movement.
- Parallel sales cannot drive available stock below the configured policy.
- Any failure before commit leaves no partial movement, balance, source transition or outbox event.
- A committed movement is immutable to application roles.
- Compensating movement preserves the original history.
- Unauthorized actor, inactive identity, wrong store/location and customer session are rejected.
- Pick-only warehouse activity does not decrement on-hand stock.
- Fulfillment completion posts exactly once.
- Transfer dispatch and receipt preserve in-transit quantity and are idempotent.
- Count submission does not post a variance until authorized approval.
- Returned devices remain quarantined until authorized inspection disposition.
- Serial/IMEI duplicate and custody checks work without leaking the full identifier.
- RLS and grants deny cross-store reads/writes.
- Existing POS, customer/employee sign-in, catalog and warehouse regression suites pass.

## Release blockers

Do not author or apply a production migration until the actual canonical inventory and identity schema is inspected. Do not report database implementation, test success, or deployment from this contract alone. Build 010.77 is complete only after an additive migration is implemented, validated against a disposable database and the target Supabase project, reviewed, reconciled, and deployed through the approved release process.
