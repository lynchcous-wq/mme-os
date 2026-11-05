# Build 008 — Inventory Data Flow and Transaction Boundary Design

**Design branch:** `build-008-inventory-foundation`  
**Evidence branch:** `integration/build001-catalog-inventory`  
**Status:** Proposed integration design based on inspected Build 001 migrations; not an implementation or deployment record.

## 1. Non-negotiable ownership

Build 008 is an orchestration and gap-closure layer over existing owners. It does not create replacement ledgers.

| Record / state | Authoritative owner |
|---|---|
| Product, model attributes, active state, catalog publication/version | Build 001 product/catalog |
| Aggregate quantity and weighted-average unit cost | `mme_inventory_balances` |
| Aggregate receipt/adjustment/transfer history | `mme_inventory_receipts`, `mme_inventory_movements` |
| Serialized physical device and unit status | `mme_serialized_units` |
| Serialized unit movement | `mme_serialized_unit_movements` |
| Customer order and payment status | Existing order/payment lifecycle |
| Checkout reservation for aggregate stock | `mme_inventory_reservations` and lines |
| Non-checkout channel hold | `mme_channel_stock_claims` and lines |
| Receipt-level cost pool and line allocations | `mme_inventory_landed_cost_pools`, allocations |
| Inspection decision and immutable disposition | Existing inspection/disposition tables and resolver |
| Customer relationship and quote/lead ownership | Build 007 CRM, once implemented and approved |
| Employee identity and action/location permission | Build 004 Identity Matrix, after approved integration |
| Durable tasks and notifications | Build 006 workflow/task owner |

A product is either aggregate-quantity managed or serialized-unit managed for a given stock flow. Do not count a serialized unit again in an aggregate balance. Do not infer a product's stock model from the request payload.

## 2. Canonical transaction flows

### A. Aggregate receiving

1. Authenticate caller and resolve the MME person identity using Build 004.
2. Authorize receiving action and trusted destination location; validate supplier/PO and approval policy outside the database mutation boundary.
3. Validate each product is active, aggregate-managed, and each location is active. Reject duplicate product/location lines.
4. Call the existing receiving RPC (or landed-cost wrapper) once for the complete receipt.
5. Inside the database transaction: lock product and balance rows in deterministic order; create receipt; update balance and weighted-average cost; append movement rows with actor, approver, reason and receipt reference; append cost pool and per-line allocation when using landed cost.
6. Commit all stock, movement, receipt and allocation changes together. Any exception rolls back the entire transaction.
7. Emit a durable Build 006 outbox/task event only after commit, with a stable event/idempotency key. Notification failure must not reverse or duplicate stock.

**Existing implementation evidence:** `mme_receive_inventory` locks product and balance rows, updates aggregate balance and inserts receipt movements. `mme_receive_inventory_with_landed_cost` delegates to that receipt RPC and then creates pool/allocation records in the same PostgreSQL function transaction. Current allocation methods are extended acquisition value and equal per unit.

### B. Serialized receiving

1. Authenticate and authorize receiving at the trusted location.
2. Validate product is active and serialized; validate one physical unit per row, serial/IMEI format, duplicate identifiers and purchase-order provenance.
3. Use the existing serialized receiving RPC, not the aggregate receipt RPC.
4. Lock product/identifier uniqueness, insert the serialized unit and immutable receiving provenance/movement record under one transaction.
5. Do not publish as available until required inspection, condition, cost and evidence gates are satisfied.
6. Commit; publish an outbox event after commit.

**Existing implementation evidence:** `mme_receive_serialized_unit` exists and the serialized-unit table has unique serial numbers plus optional IMEI. The inspected base does not establish encryption or masking of these text values. Serialized checkout was originally marked disabled pending dedicated reservation/payment review.

### C. Aggregate inventory adjustment

1. Authenticate, resolve identity and authorize adjustment at product/location scope.
2. Require non-empty reason and source/reference; enforce approval separation for high-risk adjustments/write-offs.
3. Call `mme_adjust_inventory` once.
4. Database locks product and balance, prevents negative stock and prevents reducing on-hand below reserved quantity, updates balance and appends movement evidence atomically.
5. Create any exception task after commit.

Do not perform a route-level read-modify-write. Do not update balances directly from application code.

### D. Aggregate transfer

1. Authenticate and authorize source and destination locations independently.
2. Validate active product, distinct locations, quantity and reason.
3. Call `mme_transfer_inventory` (or approved transfer lifecycle RPC where multi-step dispatch/receipt is required).
4. Lock source and destination balances in deterministic product/location order; validate unreserved source quantity; write paired movement records with one transfer correlation ID.
5. If transfer requires in-transit custody, use the existing transfer lifecycle and reconcile destination receipt before making stock sellable.
6. Emit transfer tasks/events after commit.

**Open design point:** The simple transfer RPC and later approval/in-transit transfer migrations must be crosswalked before selecting one API. Do not combine their states or invent a second transfer ledger.

### E. Aggregate channel claim

1. Authenticate and authorize the channel action, including the relevant customer/quote/auction ownership through Build 007 where applicable.
2. Verify the source reference is real and belongs to the caller/authorized employee; do not trust a bare client-supplied reference.
3. Call `mme_create_channel_stock_claim` with stable source type/reference and idempotent source identity.
4. Database locks each balance row, checks `on_hand_quantity - reserved_quantity`, increments reserved quantity, and inserts claim lines atomically.
5. On cancellation/expiry, call `mme_release_channel_stock_claim`; it locks claim/lines and decrements aggregate reservations with invariant checks.
6. On conversion to a paid order, use one reviewed atomic conversion boundary that transfers the claim into the order reservation/payment lifecycle without an availability gap or double reservation.

**Critical gap:** Existing order reservations and channel claims both affect aggregate `reserved_quantity`, which helps share the stock ceiling, but their conversion/ownership contract must be proven. The inspected schema does not establish one atomic claim-to-order-reservation conversion API. Do not implement a two-step release-then-reserve sequence.

### F. Serialized channel claim and checkout

1. Authorize the specific unit and source/quote/customer scope.
2. Lock the serialized unit and product row; require matching product/location and `unit_status='in_stock'`.
3. Change unit to `reserved` and insert the claim line in one transaction.
4. Release must restore `in_stock` only if no other active serialized reservation owns the unit.
5. Payment consumption must bind the exact unit to the order and be idempotent; it must never decrement aggregate stock for a serialized unit.
6. Failed/expired payment releases the same unit only after verifying the exact claim/reservation ownership and current state.

**Critical gap:** The existing order payment/reservation RPC shown in the inspected migration consumes aggregate reservation lines. Serialized checkout was explicitly described as disabled in the serialized-unit foundation migration. Build 008 must not enable serialized online checkout until a dedicated, tested atomic order-reserve/verified-payment-consume/refund-recovery contract exists.

### G. Payment webhook and order inventory consumption

1. Verify Stripe signature and event authenticity at the server boundary before invoking the database RPC.
2. Pass provider event ID, event type, object ID, order ID, amount, currency and payload digest to `mme_process_verified_payment_event`.
3. Database inserts the unique provider event; duplicate provider event ID returns duplicate without consuming stock again.
4. Lock order and reservation, validate exact amount/currency/order status and reservation expiry.
5. On success, consume reserved aggregate quantities and update order/payment/reservation states in one transaction.
6. On failure/expiry, release the reservation and record the failure/refund-review outcome.
7. Any external refund or notification is a separate idempotent provider action driven by durable state; never claim refund success from a database status update alone.

### H. Inspection and disposition

1. Authenticate and resolve distinct person identity.
2. Authorize inspection submission and evidence attachment for the trusted unit/location.
3. Require tests/photos/condition checklist and preserve private evidence access.
4. Resolution requires separate approval and resolution authority as specified by Build 004; enforce non-self approval and current unit/inspection state.
5. Call the existing resolver once; it locks inspection/unit and appends immutable disposition ledger evidence with resulting unit status.
6. A failure in any precondition rolls back the state transition. Never directly edit or delete a disposition row.
7. Build 017 owns return eligibility/inspection decision; inventory applies only an approved disposition event.

## 3. Locking, idempotency and event contract

- Lock inventory rows in deterministic order: product ID, location ID, then balance/unit ID. Existing RPCs do not all demonstrate a single documented global order; review each before cross-domain composition.
- Lock the parent order/claim/receipt/transfer before dependent lines, and document any exceptions to avoid deadlocks.
- Unique source keys must be stable across retries: provider event ID, receipt reference, claim source type/reference, transfer reference and client command idempotency key.
- Replaying a successful command must return the original result or a defined duplicate response; it must not create a second movement, receipt, claim, allocation or payment consumption.
- Movement/claim/payment state mutation and its authoritative ledger record must commit or roll back together.
- Use a transactional outbox for downstream Build 006 tasks/events. Consumers must be idempotent; dead-letter and replay operations must preserve the source event ID.
- Never call an external provider while holding inventory row locks. Persist a pending external action and use retryable worker execution.
- All timestamps are UTC; money is integer minor units plus explicit currency; quantities and units of measure are explicit.
- Every privileged mutation must record canonical person identity, reason, source reference, correlation/idempotency key, and approver when policy requires it.

## 4. Security and privacy boundaries

- Route: authenticate -> resolve person identity -> authorize action/resource/location -> validate trusted records -> call service-role-only RPC.
- Service-role key remains server-only. RPC privilege is not end-user authorization.
- Ignore request-provided actor/approver IDs. Derive actor identity from authenticated session mapping and approver from independently authenticated approval workflow.
- Derive product/location and current state from locked database rows.
- Public catalog projection may expose product content and appropriately aggregated availability only. Never expose serial, IMEI, supplier, cost, internal unit IDs, inspection notes, evidence paths or employee identifiers.
- Identifier reveal requires explicit purpose, narrow role/scope, masking by default, immutable reveal audit, rate limits and export denial unless separately approved.
- CRM customer references are not employee identities. Customer data must be minimized in inventory events and logs.

## 5. Required transaction-level test scenarios

| Transaction | Required test cases |
|---|---|
| Aggregate receipt | multi-line commit; duplicate product/location rejected; inactive product/location rejected; overflow/invalid cost; injected failure on final movement rolls back receipt and balances; concurrent receipt serialization |
| Serialized receipt | duplicate serial/IMEI; wrong product model; wrong location; failed inspection does not publish; no raw identifier in public API/log |
| Adjustment | positive/negative; cannot go below zero/reserved; missing reason/actor; unauthorized scope; approval mismatch; rollback when movement insert fails |
| Transfer | source insufficient; same source/destination; concurrent transfer; deterministic locking; partial in-transit receipt; duplicate receipt; missing/damaged unit reconciliation |
| Aggregate claim/order | concurrent claim race; simultaneous checkout and quote; duplicate command; expiry vs payment race; claim-to-order conversion atomicity; no oversell |
| Serialized claim/order | concurrent claim for same unit; claim release vs order reservation; duplicate payment; failed payment recovery; no aggregate decrement; unit ownership trace |
| Payment | bad signature rejected before RPC; duplicate provider event; wrong amount/currency/object; late success after expiry; webhook retry; refund pending/failure/replay |
| Inspection/disposition | unauthorized actor; terminated/frozen employee; scope mismatch; self-approval; concurrent resolutions; evidence rollback; immutable ledger |
| Events | commit then worker outage; duplicate delivery; out-of-order delivery; dead-letter/replay; task failure never mutates stock |

## 6. Decision log and blockers

1. **Reuse, do not duplicate:** existing Build 001 ledgers and RPCs remain authoritative.
2. **No serialized checkout enablement:** existing payment consumption is aggregate reservation oriented; serialized flow requires dedicated contract and tests.
3. **No two-step stock conversion:** channel claim to order reservation must be one atomic conversion or a carefully proven shared reservation owner.
4. **No direct route-level mutation:** all balance/unit transitions go through reviewed transactional RPCs.
5. **No public identifiers:** serial/IMEI protection and aggregate availability are prerequisites.
6. **No new allocation method yet:** weight/volume methods require Accounting approval and method/version/rounding tests.
7. **Build 004 gate:** PR #14 remains draft/unmerged in the reviewed state; preserve legacy checks and do not claim production cutover.
8. **Build 007 gate:** CRM is specification-only in the reviewed state; customer/quote ownership integration cannot be finalized until schema/API contracts are implemented and approved.
9. **Build 017 gate:** return/disposition ownership must be verified before returns integration.
10. **No production changes:** this design is a proposed boundary map only.

**Recommended next implementation-ready artifact:** a requirements-to-owner matrix identifying each Build 008 feature as (a) already implemented in Build 001, (b) needs hardening in the existing owner, or (c) genuinely new and awaiting approval. After that, select one bounded P0 work package only when the Build 004 and Build 007 dependencies are cleared.
