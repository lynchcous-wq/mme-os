# Build 009.1 — POS Transaction Lifecycle & Module Contract Crosswalk

**Branch:** `implementation/build-009-enterprise-pos`
**Review type:** Read-only source inspection and architecture decision record
**Status:** Contract baseline drafted; implementation blocked on unresolved module ownership and payment/tax provider contracts
**Specification:** `docs/BUILD-009-ENTERPRISE-POS.md`

## 1. Purpose and authority

This document defines the first Build 009 implementation gate: reuse verified Build 001/008 transaction and inventory ownership, identify the exact limits of existing order/payment functions, and define a POS orchestration lifecycle without creating competing ledgers.

It is not evidence of a deployed POS, working payment integration, live tax calculation, register/device support, or production readiness. No schema, application runtime, provider account, or live transaction was changed for this stage.

## 2. Verified repository contracts

| Existing owner / artifact | Verified behavior in inspected source | Build 009 use and limitation |
|---|---|---|
| `mme_orders` and `mme_order_lines` (Build 001 migration `20261103000600`) | Existing order header, idempotency key + request fingerprint, customer reference, USD totals in integer cents, pickup/shipping fulfillment snapshot, line snapshots and order status | Reuse as the authoritative order record. Do not create a second POS sale/order table. Existing status set is `pending_payment`, `paid`, `payment_failed`, `cancelled`, `expired`, `partially_refunded`, `refunded`, `disputed`; it does not distinguish cash paid, split tender, partially tendered, manager hold, or reconciliation hold. Do not overload these states without owner approval. |
| `mme_create_order_and_reserve` (Build 001) | Creates an idempotent pending order, snapshots current `mme_products` price/title/SKU/condition, calculates subtotal, then reserves aggregate inventory within the same DB transaction. Tax, fulfillment and discount inputs are expected to be calculated by a trusted server before call. | Candidate aggregate checkout entry point only after caller authorization and trusted totals are supplied. It rejects serialized products. POS must not trust browser price/tax/discount values. |
| `mme_reserve_inventory` (Build 001) | Server-only reservation RPC; pending order required; max 30-minute expiry; deterministic product/location iteration; locks product/balance; aggregate-only; validates availability and duplicate lines | Reuse only through approved server orchestration. Reservation is not a sale and does not prove payment. |
| `mme_release_order_reservation` (Build 001 lifecycle) | Releases active reservation and transitions pending order to one of `payment_failed`, `cancelled`, `expired` | Use only for the defined pending-order failure/expiry path. Do not call for a completed payment or use as a generic cart cancel. |
| `mme_process_verified_payment_event` (Build 001 lifecycle) | Accepts only Stripe `payment_intent.succeeded` / `payment_intent.payment_failed`, USD and verified event metadata; deduplicates by provider/event ID; checks exact amount/order/reservation state; consumes aggregate reservation and marks order paid atomically | This is a Stripe aggregate-order webhook processor, not a general POS tender API. It explicitly returns `use_serialized_payment_processor` for serialized order lines. It cannot represent cash, gift card, financing, split tender, partial capture, card terminal status, or multiple tender allocations. Do not call it for cash or arbitrary client claims. |
| `mme_payment_events` (Build 001) | Unique Stripe provider/event ID ledger with event type/object/order, processing state and payload digest | Reuse as Stripe webhook deduplication evidence. It is not a complete tender, refund, settlement, or POS payment-allocation ledger. |
| Channel claim conversion (migration `20261103006000`) | `mme_convert_channel_claim_to_order` atomically converts an active claim into an order + reservation without double-reserving; supports either serialized or aggregate claim mode, rejects mixed mode; serialized order lines are separately recorded | Candidate only when a valid Build 008 claim already owns stock. Its existence does not mean the current Stripe webhook processor can consume serialized reservations. The processor explicitly defers serialized lines to a separate handler. |
| `/api/cart/validate` | Public cart validation reads catalog/price/availability and returns a note that no stock is reserved and no payment is created | Validation only. It is not a POS checkout endpoint and must not be presented as completed checkout. |
| Build 008 transaction-boundary crosswalk | Documents aggregate vs serialized ownership, channel claims, reservation conversion, server-only RPC execution, idempotency, row locking, privacy and outbox boundaries | Preserve these controls. In particular, no two-step release-then-reserve conversion and no direct route-level stock mutation. |

## 3. Critical gaps discovered

### 3.1 One order status is not a tender state machine

Existing order status is too coarse to describe POS tender attempts and register cash reconciliation. Do not add meanings such as `cash_paid`, `split_paid`, or `terminal_pending` to `mme_orders.status` without an owner-approved migration and downstream compatibility review.

The POS needs explicit transaction orchestration state distinct from:
- order/fulfillment state;
- inventory reservation/serialized-unit reservation state;
- payment provider intent/charge/refund state;
- tender allocation state;
- register session/cash drawer state;
- accounting posting/reconciliation state.

The authoritative owner for tender allocation and payment lifecycle must be confirmed as Payments Center before schema design. The inspected branch does not establish that service or API contract.

### 3.2 Existing payment function is Stripe + aggregate only

The existing verified webhook function only processes two Stripe event types, requires USD, and atomically consumes aggregate inventory reservations. Serialized orders are explicitly routed away to a separate processor. This means:
- cash cannot be represented by a Stripe payment event;
- split tender cannot be safely modelled as one exact-total Stripe event without a separate allocation contract;
- card-present terminal integration is not established by this RPC;
- serialized POS checkout requires a verified serialized payment processor;
- partial authorization/capture and refunds need explicit owner contracts;
- a successful provider event after order expiry can require a durable refund-review/reconciliation path.

No POS code may route all tenders through this Stripe-only function.

### 3.3 Source-of-truth overlap must remain controlled

Build 009 must not add a second product catalog, inventory balance, serialized-unit ledger, order ledger, payment event ledger, or commission calculation. It may add register-session records and orchestration/audit records only after ownership is approved and the design proves they are not duplicating Build 001 or the future Payments Center.

### 3.4 Missing external contracts

The inspected source does not establish tax provider, terminal/acquirer certification, Verifone M425 SDK compatibility, printer/drawer integration, gift-card processor, financing provider, accounting API, commission API, or a deployed Build 017 returns API. All remain gated.

## 4. Proposed POS lifecycle (logical, not yet database enums)

| Stage | Logical state | Required evidence / guard | Failure behavior |
|---|---|---|---|
| 1. Register | `register_open` | Authenticated active employee; person-keyed permission; approved store/register scope; opening cash count if cash enabled | Deny session creation; audit denial |
| 2. Cart | `draft` | Published catalog item, current approved price/promotion version, selected store, authorized customer/attribution fields | Keep draft; revalidate on every material change |
| 3. Stock | `reservation_pending` → `reserved` | Existing aggregate reservation or serialized claim/reservation contract; idempotency; expiry; ownership and scope | Do not initiate tender until required stock is reserved |
| 4. Calculation | `calculation_pending` → `calculated` | Trusted pricing/discount and approved tax/fulfillment services; integer minor units and currency | Block tender if tax/pricing is unavailable or stale under policy |
| 5. Tender | `tender_pending` → `partially_tendered` / `fully_tendered` / `declined` / `unknown_reconciliation` | Payments Center/provider-confirmed tender allocation, idempotency and verified asynchronous evidence | Unknown result is never auto-retried; reconcile provider before retry |
| 6. Finalize | `finalization_pending` → `finalized` | All required tender accepted/authorized under policy; order and inventory conversion/consumption succeeds exactly once | Preserve durable exception; do not show success or duplicate charge |
| 7. Receipt | `receipt_pending` → `issued` / `print_failed` | Finalized transaction snapshot, approved receipt template/version and verified tender state | Print/delivery failure does not reverse payment or sale; allow audited reprint |
| 8. Downstream | `downstream_pending` → `accounted` / `commission_queued` / `exception` | Durable event/reference, idempotent consumer acknowledgements | Retry via outbox/dead-letter; never roll back a completed sale because notification failed |
| 9. Register close | `close_pending` → `closed` / `variance_review` | Expected vs actual tender/cash totals, manager verification and exception review | Preserve discrepancy and block unauthorized close override |

These are logical workflow labels for design discussion, not approved enum values or a proposed single status column. Each state belongs to its owning domain. A future implementation should use explicit transition commands and an event/audit history rather than one overloaded status.

## 5. Required invariants

1. **No false completion:** A cart, stock reservation, payment intent, terminal screen, print job or browser redirect is not a completed sale.
2. **One authoritative order:** Build 001 `mme_orders` remains the order owner unless a reviewed migration explicitly replaces it.
3. **One stock owner:** Build 008/Build 001 reservation and serialized-unit ledgers remain authoritative. No POS balance writes.
4. **One payment owner:** Payments Center/provider owns tender/payment/refund truth. The current Stripe event table is only verified Stripe event evidence.
5. **No double tender:** Each tender operation has a stable idempotency key and independently reconciled provider reference; retries of unknown outcomes first query/reconcile provider state.
6. **No premature stock consumption:** Reserve before tender where policy requires; commit/consume once on authoritative verified payment/finalization; release only through owning RPC.
7. **Serialized separation:** Serialized and aggregate stock remain disjoint. The existing Stripe aggregate handler is never used for serialized orders.
8. **Cash is not a card event:** Cash tender is recorded only through an approved server-side Payments Center/register contract with actor, register, amount, currency, change and audit evidence.
9. **Tax provenance:** Persist calculation provider/reference, jurisdiction, product tax classification, basis, rate/version, timestamp, rounding and response digest/reference. No hardcoded permanent rates.
10. **Receipt is a projection:** Receipt derives from finalized order, approved tax/tender records and versioned company template. Reprint cannot re-charge or recreate inventory movement.
11. **Independent failures:** Drawer/printer/outbox/accounting/commission failures do not reverse a provider-confirmed payment or completed inventory transition.
12. **Privacy:** No raw PAN/CVV/PIN/track data; no public serial/IMEI, supplier cost, employee private identity, or internal evidence/storage key.
13. **Actor authority:** Derive actor and approver from authenticated server-side person identity; never accept request-body actor IDs or trust UI visibility.
14. **Auditability:** Privileged discounts, price exceptions, attribution changes, cash opens, voids, refunds, drawer opens, reprints and close variances require reason, actor, scope, timestamp and immutable evidence.

## 6. Contract ownership matrix and implementation blockers

| Capability | Intended owner | Existing evidence | Gate before Build 009 implementation |
|---|---|---|---|
| Product & published price | Build 001 Catalog / approved Pricing | Existing catalog/product route and price snapshot logic | Confirm canonical source product ID and approved price/promotion version; avoid parallel catalog |
| Aggregate inventory | Build 001/008 Inventory | Reservation and payment-consumption RPCs | Route auth + contract tests; ensure store/register location scope |
| Serialized inventory | Build 001/008 Inventory | Serialized-unit reservation and claim conversion; separate payment path required | Identify and test exact serialized payment processor before enabling POS sale |
| Order lifecycle | Build 001 Order Management | `mme_orders`, order lines, reservation RPCs | Confirm POS order channel attribution and allowed status transitions |
| Employee / register authorization | Build 004 Identity Matrix | Person identity and person-keyed authorization functions | Confirm latest CI, dual-control/legacy parity and register/location action scopes |
| Customer / CRM | Build 007 | Documentation only in inspected repository; runtime contract not verified | No CRM/customer history integration until API/schema/auth contract exists |
| Tender allocations | Payments Center (target owner) | No verified general tender allocation service in inspected tree | Define service/API and state model before cash, split tender, gift card or financing |
| Stripe online/card payment | Payments Center + Stripe | Existing webhook event processor for aggregate order | Verify account/environment/secrets/webhook route; use test mode; preserve webhook raw-body signature verification |
| Card-present terminal | Payments Center + certified processor | No verified device integration | Verify exact M425 firmware, processor/acquirer certification, SDK and supported transaction methods |
| Tax | Approved tax service | No verified provider/API | Provider/jurisdiction decision and sandbox contract |
| Cash/register/drawer | POS + Payments Center | No verified register-session/cash ledger/device route | Approve cash reconciliation and no-sale/manual-open controls |
| Receipts/printer | POS + Brand Settings | No verified receipt template/printer API | Approve versioned template, data allowlist and supported printer |
| Returns/refunds | Build 017 + Payments Center + Inventory | Spec dependency only; runtime contract not verified | Confirm original-tender/refund API and independent inventory disposition flow |
| Commission | Commission Management | No verified runtime contract | Publish eligible transaction event contract; POS must not calculate payroll |
| Accounting | Accounting | No verified posting API | Define source reference, idempotency, reconciliation and exception acknowledgement |
| Notifications/tasks | Build 006 | Specification exists; delivery contract not verified | Transactional outbox/event contract and idempotent consumer |

## 7. Architecture decisions for this stage

- **ADR-009-001 — Reuse Build 001 orders.** No second POS order/sale ledger.
- **ADR-009-002 — Reuse Build 008 inventory ownership.** POS may orchestrate only through reviewed APIs/RPCs; no direct balance/unit mutation.
- **ADR-009-003 — Treat current Stripe webhook function as aggregate-only.** It is not a universal tender processor and is not valid for cash or serialized checkout.
- **ADR-009-004 — Separate order, stock, tender, register and accounting states.** No overloaded single transaction status.
- **ADR-009-005 — Defer tender schema and cash acceptance.** The Payments Center runtime contract is not present in inspected source; defining a second payment ledger now would create source-of-truth conflict.
- **ADR-009-006 — Provider and hardware integrations remain disabled.** No verified tax provider or M425/acquirer certification in repository.

## 8. Next bounded work package

Before adding checkout routes or UI that can submit a sale:

1. Verify Build 004 authorization workflow status and the canonical person identity helper on this branch.
2. Inspect and map the existing serialized reservation/payment processing functions and prove the webhook event route's trust boundary.
3. Define the missing Payments Center interface: tender intent, allocation, authorization/capture, cash acceptance, refund, webhook event, reconciliation, idempotency and failure states.
4. Add isolated PostgreSQL contract tests for the exact existing order/reservation/payment functions used by POS.
5. Review the resulting API contract and transaction state ownership with explicit no-live-transaction acceptance criteria.

Until these gates pass, Build 009 may build a non-mutating design/prototype shell only. It must not create a live register session, accept cash/card, reserve stock, capture payment, finalize sales or issue receipts as paid.

## 9. Scope and verification limits

This crosswalk is based on source files inspected in the Build 009 implementation branch, including Build 001 order/reservation migrations, the atomic channel-claim conversion migration, the cart validation route, and the Build 008 inventory transaction-boundary document. It does not execute SQL, prove deployed behavior, verify Stripe account settings, contact tax/device vendors, or establish production controls. Any later implementation must independently test the current migration state and API contracts.
