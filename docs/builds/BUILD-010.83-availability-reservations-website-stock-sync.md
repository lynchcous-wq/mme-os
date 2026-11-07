# Build 010.83 — Inventory Availability, Reservations & Real-Time Website Stock Synchronization

**Status:** Additive implementation contract committed on an isolated feature branch. No live inventory ledger, reservation API, availability service, storefront stock feed, migration, or deployment is claimed.

## 1. Audit findings

Repository searches on the Build 010.82 line did not locate verified inventory availability, available-to-promise, reservation, reservation-expiry, or website stock synchronization runtime components. The canonical Build 008 inventory document explicitly says the inventory ledger, reservation service, product database, and live website inventory sync are not established by that specification. It defines the required boundaries and controls, but is not evidence of runtime implementation.

The existing POS integration contract also requires inventory reservation to remain distinct from sale, payment, and fulfillment. The audited POS transaction creation route is not proof that an active inventory reservation exists or that a sale has committed stock.

Before runtime work, inspect the deployed catalog, inventory ledger, location master, order/quote/POS state machines, identity/RLS policies, website platform, cache/CDN, event transport, and deployment configuration. Do not assume Wix or any other storefront provider is configured. Do not invent canonical tables, RPC names, or provider credentials.

## 2. Objective

Deliver a trusted, location-aware availability view and concurrency-safe reservation lifecycle shared by the MME website, POS, approved quotes/Deal Desk, pickup, and shipping. Prevent overselling while keeping inventory, listing publication, order, payment, and fulfillment states separate.

## 3. Systems of record

| Information | Authority | Consumer rule |
|---|---|---|
| Product/model and public product details | Canonical Catalog / approved publication workflow | Website displays only approved public fields |
| Physical stock, unit custody, holds and movements | Canonical Inventory ledger | Availability is derived from this authority; no storefront stock edits |
| Location and operating scope | Canonical location master | Every result is scoped to valid locations and channels |
| Order and sale state | POS / Order Management | Reservation is consumed only by authorized order/sale transition |
| Payment state | Payment provider and verified server-side webhook/event | A browser success screen does not prove payment |
| Approved selling price | CEO-authorized Pricing System | Stock sync never changes price |
| Customer and employee identity | Identity Matrix / Supabase Auth integration | Server-side authorization and purpose-limited customer linkage |
| Public website listing state | E-commerce publication workflow | Listing approval is separate from physical availability |

If an authority is not verified in runtime, treat it as a blocker and record the dependency.

## 4. Availability model

The service must distinguish, never conflate:
- Physical on-hand.
- Reserved/held.
- Available-to-promise (ATP).
- Incoming / expected.
- Inspection, quarantine, damaged, or otherwise blocked.
- Transfer-in-transit.
- Sold/fulfilled.
- Written off.

ATP must be derived using an approved, versioned policy from eligible stock, location, reservation, safety-stock, condition, and channel rules. Do not assume a universal arithmetic formula before finance/operations approve the policy. In-transit, incoming, quarantined, inspection-required, damaged, sold, and written-off quantities are excluded from immediate availability unless an explicitly approved policy says otherwise with customer-facing disclosure.

Every availability response includes:
- Stable product and, where applicable, location references.
- Quantity class and sellable quantity (or a safe availability band).
- Channel eligibility (in-store, pickup, shipping, approved quote hold).
- Source revision/version and generated-at timestamp.
- Freshness/expiry metadata and policy version.
- A clear unavailable/unknown/stale result rather than a fabricated zero or positive count.

Serialized devices must be available by eligible unit identity and condition, while serial/IMEI remains encrypted, masked, and absent from public payloads.

## 5. Reservation lifecycle

Required logical states:
1. **Requested** — a channel requests quantity/unit and location.
2. **Validated** — product, location, policy, customer/order context, and current inventory revision are checked.
3. **Reserved** — stock is atomically held against a stable reservation ID and expiry.
4. **Committed** — the owning POS/order workflow confirms the authorized sale/fulfillment milestone and consumes the reservation exactly once.
5. **Released** — cancellation, failure, or authorized expiry releases the hold exactly once.
6. **Expired** — expiry worker marks the reservation expired and requests idempotent release; it must not leave phantom holds.
7. **Exception** — conflicts, stale versions, failed posting, or mismatched order state require reconciliation.

A quote hold is not an order, sale, or payment. Reservation must be bound to source channel, product/unit/quantity, location, order/quote reference, actor/customer context as authorized, creation/expiry, policy version, idempotency key, and audit/correlation IDs.

## 6. Concurrency, idempotency and transaction rules

- Reserve through one server-authorized atomic operation or equivalent concurrency-safe ledger transaction.
- Concurrent requests must never reserve more eligible stock than exists.
- Use stable idempotency keys and request hashes; replay with same identity returns the original result, while conflicting reuse is rejected.
- Reservation creation, balance update/derivation, and durable event/outbox write must be atomic where possible.
- Commit and release are mutually exclusive terminal operations for a reservation; repeated calls are safe.
- A reservation cannot be committed against a different product, location, order, quantity, or revision.
- Use explicit lease/expiry semantics and a durable worker; client timers do not release stock.
- If inventory authority is unavailable, stale, or inconsistent, fail safely under an approved channel policy. Never claim stock is available from stale cache.
- Reconcile duplicate/out-of-order events and abandoned reservations without rewriting immutable movement history.

## 7. Website and channel synchronization

- Website receives availability only through an authenticated, versioned, allowlisted server API/event contract.
- Catalog publication owns listing content and state; inventory supplies eligible availability. Neither system silently overwrites the other.
- Publish product listing and availability separately. A Coming Soon item must disclose not-yet-available status and cannot be purchased as immediately available.
- Never expose internal unit cost, supplier records, serial/IMEI, customer data, restricted inspection evidence, employee details, or raw inventory ledger payloads.
- Sync events include stable event ID, product/location references, source revision, policy version, generated-at time, and correlation ID.
- Consumers are idempotent and reject stale/out-of-order revisions. Reconcile the website projection against canonical inventory.
- Cache TTL, revalidation, purge, and stale fallback are explicit and tested. A cache hit must not bypass a reservation check at checkout.
- Search/listing pages may show a freshness-qualified estimate; the final cart/checkout action must revalidate and atomically reserve.
- If real-time inventory cannot be confirmed, show an honest unavailable/verification-needed message and prevent an unverified stock promise.
- Verify the actual production website provider and integration before implementing provider-specific webhooks or APIs.

## 8. Customer and employee experience

Customer experience:
- Display approved product details, condition, price, pickup/shipping eligibility, and freshness-qualified availability.
- Recheck availability when adding to cart and again at checkout.
- Show reservation/hold expiry only when a real server-side reservation exists.
- Present unavailable, Coming Soon, low-stock, and location-specific states without exposing internal quantities or restricted records.
- Preserve customer sign-in and existing account identity.

Employee experience:
- Search availability by product, location, and channel.
- Create authorized pickup, POS, and quote holds.
- View reservation status, expiry, source, and exception reason within role scope.
- Release or override only with explicit permission, reason, and audit trail.
- Preserve employee sign-in and role/location restrictions.

## 9. Automation and monitoring

Use durable workers/events for reservation expiry, abandoned-cart cleanup where policy permits, stock projection refresh, cache invalidation, stale-feed detection, webhook retry, and reconciliation. Notification failure must not change stock or reservation state.

Monitor:
- ATP versus ledger balance reconciliation.
- Reservation success/conflict rate and age.
- Expired-but-not-released reservations.
- Duplicate/replayed command counts.
- Website projection lag and stale cache responses.
- Checkout reservation failures and oversell incidents.
- Failed outbox events and retry exhaustion.

Escalate exceptions through the existing workflow/notification authority after verifying its runtime contract.

## 10. Security and privacy

- Enforce server-side role, action, channel, customer, and location scope.
- RLS protects source records; public API returns only explicit allowlisted fields.
- Service-role credentials remain server-side.
- Prevent customer A from viewing customer B's holds, orders, or identity references.
- Prevent employees from reserving or releasing outside their assigned scope.
- Mask serial/IMEI and avoid putting restricted identifiers in logs, analytics, URLs, or public events.
- Audit availability overrides, reservation creation/commit/release/expiry, policy changes, sync failures, and exception resolution.

## 11. Acceptance and regression tests

- ATP reconciles to eligible canonical ledger quantities by product, unit, location, and channel.
- Reserved, incoming, in-transit, damaged, quarantined, sold, and written-off stock is excluded from immediate ATP according to policy.
- Concurrent checkout attempts cannot oversell the final unit.
- Replayed reservation, commit, release, and expiry events are idempotent.
- Commit and release cannot both succeed for the same reservation.
- Expiry releases stock exactly once, including worker retry and crash recovery.
- Stale inventory revision or cache cannot create a positive stock promise.
- Website sync rejects stale/out-of-order events and reconciles projection drift.
- Checkout revalidates and reserves against canonical inventory; cached display values alone cannot authorize a sale.
- Coming Soon and unreceived stock cannot be sold as immediately available.
- Public responses contain no serial/IMEI, cost, supplier, internal notes, or customer/employee data.
- Unauthorized customer, employee, channel, and cross-location requests are denied.
- Payment, order, reservation, sale, and fulfillment states remain distinct.
- Regression tests preserve customer sign-in, employee sign-in, product viewing, POS, warehouse, receiving, returns, and website behavior.

## 12. Runtime implementation gates

Do not mark Build 010.83 implemented or live until:
1. Canonical catalog, inventory ledger, reservation, location, order/POS, identity, audit, and event schemas are inspected in the target environment.
2. The actual production website platform, hosting, cache/CDN, and webhook/API ownership are verified.
3. Approved ATP, safety-stock, hold, expiry, pickup, shipping, and quote policies are documented by operations.
4. Additive migrations and RLS policies are reviewed; no parallel inventory master is introduced.
5. Availability read API, atomic reservation commands, commit/release, expiry worker, outbox, and reconciliation are implemented.
6. Website projection and checkout revalidation are integrated with authenticated, versioned, idempotent contracts.
7. Concurrency, idempotency, stale-cache, security, privacy, and end-to-end tests pass.
8. Customer and employee sign-in, product viewing, POS, warehouse, receiving, returns, and current storefront regressions pass.
9. Staging ledger/ATP/reservation/website balances reconcile with no unexplained variance.
10. Production deployment and post-deploy smoke tests are recorded with exact commit and environment.

**Release note:** This contract is not a live availability feed, reservation, stock adjustment, sale authorization, production migration, or deployment approval. No runtime feature or production stock change is claimed by this document.
