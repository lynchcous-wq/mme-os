# Build 010.78 — POS & Warehouse Inventory Posting Bridge

Status: integration contract committed on an isolated feature branch. No sale-completion endpoint, warehouse API, inventory posting RPC, or live stock mutation is claimed to have been implemented.

## Repository audit — observed facts

Inspected the current Build 010.77 branch snapshot:

- `app/api/pos/transactions/route.ts` authenticates a POS request, requires an `Idempotency-Key`, accepts an `order_id`, and calls the Supabase RPC `mme_pos_create_transaction`.
- The route then reads `mme_pos_transactions` and returns the transaction. This is transaction creation/confirmation, not evidence of payment capture, sale finalization, fulfillment completion, or inventory deduction.
- `lib/pos/authenticated-server.ts` verifies a Supabase Auth bearer token and resolves an MME person identity. Its helper name and current checks do not, by themselves, prove an inventory-specific permission or location scope check.
- The expected `app/api/warehouse/route.ts` path was not found in the audited branch. No verified warehouse fulfillment API path was established in this inspection.
- Build 008 is explicitly a specification and states that inventory, POS, warehouse and stock integration are not implemented/verified by that document.
- The database inventory schema and canonical stock posting RPC remain unverified. Build 010.77 records this blocker.

Do not infer that creating a POS transaction completes a sale. Do not attach an inventory deduction to the existing transaction-creation route.

## Objective

Create a single, idempotent bridge from authoritative POS sale completion and warehouse fulfillment completion into the canonical inventory posting engine, after the database schema and source workflows have been verified.

The bridge coordinates source events. It does not own product identity, payment state, order state, warehouse pick state, return disposition, employee identity or cost valuation.

## Source-of-truth boundaries

| Event / data | Authority | Bridge behavior |
|---|---|---|
| POS transaction creation | POS transaction service | No stock deduction |
| Sale completion / order finalization | Verified POS/order completion workflow | Request one inventory commit for eligible sold quantities |
| Payment authorization/capture/refund | Payment provider / Payments Center | Consume verified payment reference/state; never infer from UI success |
| Warehouse pick scan | Warehouse fulfillment workflow | No stock deduction |
| Pack verification | Warehouse fulfillment workflow | No stock deduction by itself |
| Shipment handoff / fulfillment completion | Verified warehouse workflow and policy | Commit stock only at the approved fulfillment milestone |
| Inventory movement and balance | Canonical inventory ledger | Sole authority for stock movement/balance |
| Return receipt and inspection | Returns workflow | Keep returned unit quarantined until authorized disposition |
| Product and unit identity | Catalog / inventory unit master | Resolve canonical IDs; do not create shadow item records |
| Employee authorization | Identity Matrix / permission service | Enforce actor, role, action and location scope server-side |

## Integration event contract

Use a versioned internal event envelope. Exact field names and database references must be aligned to the audited canonical schema before runtime implementation.

Required semantics:

- `event_id`: stable unique event identifier from the authoritative source.
- `event_type`: explicit allowlist such as POS sale committed or warehouse fulfillment completed.
- `event_version`: schema version.
- `source_system` and `source_reference`: authoritative source identity.
- `order_reference` and, where relevant, `fulfillment_reference`.
- `location_reference`: canonical source/destination location reference.
- `lines`: canonical item reference, quantity, and serialized-unit references where required.
- `occurred_at`: source event timestamp.
- `correlation_id`: trace identifier.
- `actor_reference`: resolved server-side identity or service actor; never trust a client-supplied actor as authorization evidence.

Reject malformed, unsupported, incomplete, or conflicting events. Do not include raw payment credentials, bearer tokens, or unrestricted IMEI/serial values in logs or general-purpose event payloads.

## POS sale-completion bridge

1. Discover and inspect the actual POS/order completion RPC, transaction state machine, payment verification path and order reservation model.
2. Define the precise state that represents a committed sale, including permitted tender/financing states and cancellation/reversal rules.
3. Ensure payment state is verified independently by the Payments Center/provider. A POS transaction row or browser response alone is insufficient.
4. At the authoritative sale-completion transaction, write a durable inventory-posting outbox event or invoke the canonical inventory posting RPC in the same database transaction.
5. Use a deterministic source idempotency identity derived from the immutable sale/order completion reference and line identity; do not generate a new key on retry.
6. Post only quantities eligible under the approved inventory policy. Existing reservation must be consumed exactly once; do not create a second deduction for the same reserved quantity.
7. If the inventory post is rejected, preserve truthful source state and place the operation into a recoverable exception/compensation workflow. Never mark stock deducted if the ledger did not commit.
8. If sale completion and inventory posting share a database, prefer one atomic database transaction. If they cannot share a transaction, use a durable outbox and explicit pending/posted/failed states with reconciliation.
9. A void/cancellation before fulfillment must release the appropriate reservation through an authorized source event; it must not erase posted history.
10. A return/refund does not automatically restock. Build 017 or the verified return disposition workflow must authorize inventory disposition separately.

## Warehouse fulfillment bridge

1. Locate and inspect the real warehouse API, persistence model, pick wave/list state machine, pack verification and shipment/handoff confirmation.
2. Treat pick scan and pack verification as operational evidence only; neither event alone reduces on-hand stock.
3. Define the exact configured fulfillment milestone that commits stock, such as carrier handoff or approved customer pickup handoff.
4. Validate that the order has an eligible active reservation and that picked/packed quantities match the authorized order quantities.
5. Validate serialized unit identity and custody for individually tracked electronics.
6. Post the inventory movement once using a stable fulfillment/source idempotency key.
7. Record source posting status and movement reference durably; retries replay the original movement.
8. Handle short picks, substitutions, damaged goods, split shipments, partial pickup, canceled labels, carrier handoff failure and customer no-show through explicit exception/release paths.
9. Do not count in-transit transfer quantities as destination on-hand until destination receipt is confirmed.
10. Preserve warehouse evidence and actor attribution without exposing sensitive serial/IMEI values.

## Reliability and recovery

- Use transactional outbox/inbox patterns where POS, warehouse and inventory cannot commit in one database transaction.
- Enforce uniqueness on source event identity and inventory posting identity.
- Make consumers safe for at-least-once delivery and out-of-order retries.
- Track pending, processing, posted, retryable-failed, permanently-rejected and compensated states with explicit transitions.
- Use bounded exponential retry with jitter for transient failures; never retry permanent validation/permission conflicts indefinitely.
- Provide an authorized reconciliation operation that compares source completed quantities with inventory movement references.
- Reconciliation must report mismatches and propose actions; it must not silently rewrite stock.
- Ensure a timeout after commit can be safely retried using the same source identity.
- Alert the appropriate operations/IT queue on aged pending events, repeated failures, and source/ledger drift.

## Authorization and privacy

- Verify employee/service identity server-side and apply operation-specific permissions and store/location scope.
- A customer session cannot invoke employee inventory posting.
- Do not rely on UI visibility or the existing generic POS authentication helper as proof of inventory permission.
- Keep service-role credentials server-only.
- Mask serial/IMEI in routine responses, logs, audit details and notification payloads.
- Keep payment card data and provider secrets outside the event envelope.
- Record who initiated, approved, processed and reconciled each event.

## Required test matrix

- POS transaction creation alone produces no inventory deduction.
- Payment pending/declined does not commit a sale deduction.
- Eligible sale completion posts exactly once.
- Retrying sale completion with the same source identity replays the same posting.
- Concurrent duplicate completion events create one movement.
- Same source identity with conflicting line payload is rejected and alerted.
- Sale cancellation releases reservation once and does not erase prior ledger history.
- Pick scan and pack verification alone do not deduct on-hand stock.
- Confirmed fulfillment handoff posts exactly once.
- Partial shipment and split fulfillment deduct only the eligible completed quantities.
- Short pick, damaged unit and substituted item follow approved exception paths.
- Failed inventory posting remains pending/failed and is not falsely reported as posted.
- Outbox replay and reconciliation recover transient failures without duplicate movements.
- Serialized device custody checks pass and identifiers remain masked.
- Cross-location and unauthorized employee operations are denied.
- Customer sign-in, employee sign-in, catalog, POS transaction creation and warehouse workflows remain regression-green.

## Release gates

Build 010.78 cannot be marked implemented until all of the following are true:

1. The canonical inventory schema and posting RPC are inspected and verified.
2. The actual POS sale-completion source workflow is identified and tested.
3. The actual warehouse fulfillment API and completion milestone are identified and tested.
4. A reviewed additive migration and server-side bridge implementation exist.
5. Idempotency, concurrency, rollback, RLS and authorization tests pass.
6. End-to-end POS and warehouse tests prove exactly-once stock posting.
7. Existing customer/employee sign-in, catalog and sales workflows pass regression.
8. Staging reconciliation shows no unexplained stock drift.
9. Production rollout is approved, monitored and verified.

This document is a release contract only. It does not authorize a production migration, payment capture, stock adjustment, or deployment.
