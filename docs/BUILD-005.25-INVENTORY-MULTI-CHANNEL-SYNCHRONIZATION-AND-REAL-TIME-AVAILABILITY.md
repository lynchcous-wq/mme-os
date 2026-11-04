# Build 005.25 — Inventory Multi-Channel Synchronization and Real-Time Availability

**Status:** Channel synchronization and availability design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines how authoritative inventory availability is projected to the MME website, POS, auction listings, customer pickup, shipping, and approved external channels. This document does not connect channels, configure webhooks, modify code or databases, run tests, or deploy services.

## 1. Purpose

Prevent overselling, stale listings, duplicate reservations, and misleading availability across MME sales channels. Inventory Core remains the authority for physical stock and reservations. Channel displays are projections and must never independently create or adjust inventory.

## 2. Ownership boundaries

- **Build 005 Inventory Core:** physical units/quantity, location, condition, holds, reservations, movements, and authoritative availability decisions.
- **Build 001 Website:** storefront product presentation, customer-facing availability, cart experience, and local pickup selection.
- **Build 002 Orders/POS:** order creation, checkout, sale commitment, payment coordination, and receipts.
- **Auction engine / Build 005.22:** listing and bid state, reserve outcomes, auction-specific inventory holds, and settlement handoff.
- **Build 005.17:** location, warehouse, and transfer state.
- **Build 005.21:** authorized prices and price versions.
- **Build 017:** returns and refund workflow.
- **Build 026:** channel performance and synchronization reporting.

Channel systems may cache availability for display, but only Inventory Core may authorize a reservation or stock commitment.

## 3. Channel and location model

Supported channel types may include:
- MME public website;
- physical-store POS;
- local pickup;
- shipping/online orders;
- auction listings;
- approved wholesale or liquidation channels;
- approved external marketplaces, if separately authorized.

Availability must be evaluated for the requested SKU/unit, condition, channel, fulfillment method, and eligible location. A unit at one location is not automatically available for pickup at another location.

## 4. Availability contract

A channel availability response should distinguish:
- **sellable now:** eligible and uncommitted stock;
- **available for pickup:** eligible stock at a pickup-enabled location;
- **available to ship:** eligible stock at a shipping-enabled location;
- **reserved:** held for an active order or approved workflow;
- **auction committed:** held for an active listing;
- **incoming:** expected but not yet physically received and inspected;
- **unavailable:** no eligible stock or policy restriction;
- **unknown/stale:** authoritative availability cannot be confirmed.

Do not combine incoming, quarantined, damaged, display/demo, disputed, or otherwise restricted units into sellable quantity.

For serialized goods, availability is based on eligible physical units, not a client-provided count. For quantity lots, availability must account for the correct location, unit of measure, lot status, and existing reservations.

## 5. Reservation and checkout sequence

Proposed sequence:
1. Customer selects SKU, condition, fulfillment method, and location.
2. Website or POS requests a current availability check.
3. Inventory Core validates eligibility and creates a time-bounded reservation atomically.
4. Order workflow records the reservation reference and price snapshot.
5. Payment is processed only through the approved payment authority.
6. Inventory is committed at the defined successful order-commit point.
7. Failed, abandoned, or expired orders release reservations through an idempotent command.
8. Channel projections are refreshed from resulting authoritative events.

A cart display is not a reservation. A reservation is not a completed sale. Payment authorization, capture, and order commitment must remain distinct states.

## 6. Concurrency and oversell prevention

- Use atomic, server-authoritative reservation decisions.
- Enforce uniqueness and quantity constraints at the authoritative transaction boundary.
- Reject stale or duplicate client requests safely.
- Require idempotency keys for retried reservation and release commands.
- Prevent the same serialized unit from being reserved by two active orders or listings.
- Prevent quantity reservations from exceeding eligible on-hand quantity.
- Define deterministic conflict responses when POS, website, and auction activity compete for the same stock.
- Do not rely on client-side cart counts, browser state, or cached availability to authorize a sale.

## 7. Event and synchronization contract

Proposed events include:
- inventory.availability_changed
- inventory.unit_status_changed
- inventory.reservation_created
- inventory.reservation_expired
- inventory.reservation_released
- inventory.order_committed
- inventory.location_changed
- inventory.channel_hold_created
- inventory.channel_hold_released
- inventory.reconciliation_required

Events should include event ID, schema version, entity reference, source, occurred-at timestamp, correlation ID, and idempotency/deduplication reference. Do not include full serial/IMEI or unnecessary customer personal data.

Use a durable outbox/inbox pattern, retry policy, dead-letter handling, and replay controls. Consumers must be idempotent and tolerate duplicate, delayed, and out-of-order delivery.

## 8. Channel-specific rules

### Website
- Display availability with a clear location and fulfillment context.
- Refresh availability before checkout and obtain an authoritative reservation.
- Do not show incoming goods as immediately purchasable stock.
- If the source is stale, show a safe unavailable/check-again state rather than a false promise.
- Keep product description, condition, price, and availability as separately versioned facts.

### POS
- Revalidate stock at sale time.
- Support local network interruption safeguards and a controlled offline policy.
- Do not permit offline serialized-device sales unless a separately approved mechanism prevents duplicate commitment.
- Reconcile offline transactions before restoring normal availability.

### Local pickup
- Reserve stock at the selected pickup location.
- Move committed goods into pickup staging through an authorized movement.
- Track ready, collected, expired, and cancelled states.
- Release uncollected stock only through an approved cancellation/expiry workflow.

### Shipping
- Allocate from shipping-enabled locations.
- Coordinate pick, pack, shipment, cancellation, and return events.
- Do not mark shipped based solely on label creation.

### Auctions
- Listing publication requires an eligible auction hold.
- Active auction stock is excluded from other sales channels.
- A bid does not create a sale or payment.
- Reserve-not-met and cancellation outcomes release or retain holds according to approved policy.

### External channels
- Each external channel requires explicit authorization, mapping, and a defined sync contract.
- External inventory feeds are projections, never the source of MME stock truth.
- Define per-channel safety buffers only as approved policy; never use an undocumented buffer to conceal inaccurate stock.

## 9. Price and listing consistency

Availability synchronization must not overwrite pricing. Price updates are owned by Build 005.21 and must carry a price version/effective timestamp. A channel must not combine an old price with a newer condition or product record without detecting the version mismatch.

Before checkout or auction settlement, validate the applicable authorized price and record a transaction snapshot. Stale channel listings should be refreshed or suppressed according to policy.

## 10. Reconciliation and exception handling

Compare authoritative inventory with channel projections on a scheduled and event-driven basis. Flag:
- channel quantity greater than eligible inventory;
- active listing without a valid hold;
- duplicate listing or unit allocation;
- reservation without a valid order;
- order committed without corresponding inventory movement;
- stale price or condition version;
- failed event delivery;
- unexplained channel quantity drift;
- pickup/shipping status mismatch.

Reconciliation must not silently adjust stock. Create an investigation case and use authorized compensating inventory movements only after evidence and approval.

## 11. Monitoring and service objectives

Define approved service objectives for:
- availability read latency;
- event propagation delay;
- reservation success/failure rates;
- channel projection freshness;
- stale-data duration;
- oversell incidents;
- event retry/dead-letter volume;
- reconciliation exception age.

The dashboard must show source timestamp and freshness. If the system cannot verify current availability, it must fail safely and avoid promising stock.

## 12. Security and privacy

- Authenticate channel service identities.
- Authorize each channel for its permitted commands and locations.
- Validate webhook signatures and replay protections where applicable.
- Keep privileged inventory commands server-side.
- Mask serial/IMEI and customer data from channel payloads unless strictly required and authorized.
- Audit reservation, release, commit, override, and reconciliation actions.
- Apply rate limits and abuse controls to public availability endpoints.
- Do not expose internal cost, margin, supplier, or restricted inventory notes to customers.

## 13. Acceptance criteria

- [ ] Inventory Core is the sole authority for physical availability and reservations.
- [ ] Website, POS, pickup, shipping, and auction use the same authoritative reservation contract.
- [ ] Incoming and uninspected goods are excluded from sellable availability.
- [ ] Serialized units cannot be double-reserved.
- [ ] Quantity reservations cannot exceed eligible stock.
- [ ] Cart state is not treated as a reservation.
- [ ] Order, payment, and inventory commitment states remain distinct.
- [ ] Events are versioned, durable, deduplicated, and replay-safe.
- [ ] Stale or unavailable sources produce safe customer-facing behavior.
- [ ] Channel price/condition versions are validated independently.
- [ ] Reconciliation identifies drift without silently changing inventory.
- [ ] External channels require explicit approval and mapping.
- [ ] Security tests cover unauthorized channel commands, replay, and data leakage.
- [ ] Concurrency tests cover simultaneous POS, web, and auction attempts for the same stock.

## 14. Completion boundary and next gate

This is a design specification only. No channel was connected, no webhook or feed was configured, no reservation or order was created, and no live payment was attempted. No code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve channel priority/conflict rules, reservation durations, offline POS policy, pickup expiry policy, freshness objectives, external-channel scope, and reconciliation ownership before implementation.
