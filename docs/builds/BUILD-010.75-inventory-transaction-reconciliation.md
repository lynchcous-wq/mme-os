# Build 010.75 — Inventory Transaction & Stock Reconciliation

Status: implementation branch opened; design and release contract only. Runtime code and database migration are NOT yet implemented.

## Scope

Add an auditable inventory transaction layer that connects warehouse fulfillment, receiving, transfers, returns, POS sales, and physical counts to one authoritative stock ledger. This build is additive: existing catalog, warehouse, POS, and identity records remain intact.

## Required invariants

1. Every posted stock change is represented by an immutable ledger movement with a unique movement ID, source type/reference, item ID, location ID, quantity delta, actor, timestamp, and idempotency key.
2. Posted movements are append-only. Corrections use compensating movements; no silent edits or deletes.
3. Available, on-hand, reserved, and in-transit quantities are distinct. A pick scan alone does not decrement on-hand stock.
4. A source event may post at most once. Duplicate idempotency keys return the original posting result.
5. Serialized devices require serial/IMEI identity validation before a movement can post. Do not expose full IMEI values in general-purpose logs or dashboards.
6. Transfers use paired dispatch/receipt events. In-transit stock is not available at either endpoint until receipt is confirmed.
7. Physical counts create variance records. Posting an adjustment requires an authorized reviewer and a reason code; count submission itself never silently changes stock.
8. All writes enforce tenant/store scope and role permissions server-side. Client-side hiding is not authorization.
9. Financial valuation is derived from the approved cost method already used by the application; do not introduce a competing cost basis in this build.
10. Failed or partial posting leaves a durable exception and never reports success to the caller.

## Functional work packages

- Inventory movement API: validate source, item, location, quantity, permissions, and idempotency; atomically write movement and update/derive balances.
- Serial/IMEI controls: resolve device identity, reject duplicate active assignments, and record custody/location changes.
- Receiving: match purchase order lines and accepted quantities; route damaged/short quantities to exceptions.
- Transfers: create, dispatch, receive, and reconcile in-transit quantities.
- Cycle counts: open count session, capture blind count, compare against ledger, review variance, and post approved compensating movement.
- Fulfillment bridge: only post stock deduction after the warehouse fulfillment source is eligible and the posting transaction commits.
- Returns bridge: quarantine returned stock until inspection disposition authorizes restock.
- Reporting: on-hand, reserved, available, in-transit, count variance, and unresolved posting exceptions.

## Acceptance tests (release blockers)

- Concurrent duplicate requests with the same idempotency key create exactly one movement.
- A failed transaction leaves neither a partial movement nor a balance update.
- A successful sale/fulfillment produces exactly one inventory deduction.
- A pick scan without completed fulfillment produces no on-hand deduction.
- Serialized item movement rejects missing, malformed, or already-active serial/IMEI identity.
- Transfer dispatch moves quantity to in-transit; receipt moves it to destination on-hand exactly once.
- Count variance cannot post without reviewer permission and a reason code.
- Return receipt remains quarantined until an authorized disposition.
- Cross-store reads/writes are denied under row-level security and API authorization tests.
- Audit records identify actor, source, idempotency key, and before/after quantities without leaking sensitive device identifiers.
- Existing catalog, customer/employee sign-in, POS, and warehouse regression suites remain green.

## Required repository audit before runtime changes

- Inspect current inventory tables, constraints, indexes, triggers, RLS policies, and migration ordering.
- Trace the existing POS sale-completion and warehouse fulfillment posting paths.
- Identify the canonical product/item and store/location identifiers; reuse them.
- Identify current cost valuation and serialized-device sources; do not create parallel sources of truth.
- Review all current inventory write paths for bypasses before enabling ledger enforcement.

## Deployment gates

No production migration, feature flag enablement, or deployment is authorized by this document alone. Runtime implementation must be delivered as a separate additive migration/API/UI change, pass the acceptance and regression suites, and be verified in the target environment before this build is marked complete.
