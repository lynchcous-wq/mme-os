# Build 005.13 — Inventory Integration Architecture and Cross-Build Connections

**Status:** Integration architecture design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines how Inventory Core exchanges data and commands with MME OS builds and external commerce/fulfillment systems. This document does not implement APIs, adapters, webhooks, database objects, UI, credentials, tests, or deployments.

## 1. Purpose and authority

Inventory Core is the authoritative source for physical stock, stock movements, holds, reservations, and sellable availability. Connected builds may request commands or consume approved events, but must not maintain competing stock balances.

Each integration must have:
- a named source and destination;
- an explicit owner and data authority;
- a documented command/event contract and schema version;
- server-side identity and permission checks;
- idempotency, correlation, retry, and reconciliation behavior;
- a failure owner and operational runbook.

## 2. Integration patterns

### Synchronous commands
Use for operations that require an immediate authoritative result, such as reserving stock, releasing a reservation, receiving a transfer, or querying availability. Return a stable result or a typed conflict. Do not return a guessed or cached value as authoritative.

### Asynchronous events
Use the transactional outbox for committed facts such as receipt posted, movement committed, reservation expired, or reconciliation drift detected. Consumers must tolerate duplicate and out-of-order delivery and retrieve authoritative current state when event ordering matters.

### Read models
Storefront and dashboards may use purpose-built projections for speed. Projections are informational and must show freshness; they cannot authorize a sale or mutate stock.

### External webhooks
Verify provider signatures, timestamps, replay protection, and event identity. Treat webhook payloads as untrusted input. External events may request reconciliation or a business workflow, but cannot directly write inventory.

## 3. Cross-build ownership matrix

| Build / system | Inventory Core interaction | Authority boundary |
|---|---|---|
| Build 001 — Website foundation | Product listing, availability display, cart/order references | Inventory Core owns stock and reservation decisions; website owns presentation and customer journey |
| Build 002 — POS / sales workflow | Availability lookup, reservation, commit request, release | POS owns sale workflow and receipt; Inventory Core owns stock movement and reservation state |
| Build 004 — Identity foundation | Actor identity, roles, permissions, location scope | Identity owns identity and authorization; inventory does not duplicate identity tables |
| Build 008 — Inventory target specification | Requirements and inventory workflows | Build 005 is the authoritative core design; reconcile overlaps before implementation |
| Build 017 — Returns and refunds | Return disposition request, quarantine/hold, approved restock command | Returns owns inspection/disposition decision; Inventory Core records approved stock effects |
| Build 022 — Contracts / e-sign | Evidence and approvals for controlled inventory agreements where applicable | Contracts owns signed documents; inventory stores references, not document authority |
| Build 026 — Analytics | Read-only inventory facts and approved aggregates | Analytics owns reporting models; never writes stock balances |
| Build 029 — Payroll / HR adjacent workflows | Authorized staff and location context only | HR/Payroll owns employment and compensation; no inventory authority |
| Shipping / local pickup | Pick, pack, dispatch, pickup confirmation, exception requests | Fulfillment owns shipment and handoff; Inventory Core owns stock state |
| Auction engine | Listing eligibility, reservation, winning-order handoff | Auction owns bidding and auction outcome; Inventory Core owns reservable availability |
| Acquisition / COGS engine | Receipt and per-item landed-cost facts | Acquisition owns purchase/acquisition evidence and cost calculation; Inventory Core owns received stock quantities and movement history |
| Pricing engine | SKU and availability context for pricing decisions | Pricing owns price and markdown policy; inventory does not set sale price |
| CRM / customer portal | Authorized status and order references | CRM/customer portal owns customer interactions; no direct stock mutation |

This matrix is a proposed ownership map. Existing code and route behavior must be verified before implementation.

## 4. Core integration contracts

### 4.1 Catalog and SKU
Catalog supplies stable product and SKU references plus approved descriptive attributes. Inventory validates references and stores only the identifiers and minimal snapshots needed for audit. Product descriptions, images, and marketing copy are not inventory authority.

### 4.2 Website and POS availability
Consumers request availability by SKU and location. Response should distinguish:
- sellable now;
- reserved;
- held/quarantined;
- in transit;
- expected but not received;
- unavailable or unknown.

Only Inventory Core can authorize a reservation. A displayed availability projection is not a guarantee until the authoritative reservation succeeds.

### 4.3 Order and payment separation
An order workflow requests a reservation and receives a reservation reference. Payment authorization/capture is handled by the approved payment workflow. Inventory must not infer payment success from a browser redirect or unverified webhook. Sale completion requires the owning order/POS workflow to coordinate confirmed payment and the inventory commit through an idempotent, recoverable process.

No payment credentials, card numbers, or sensitive payment tokens belong in inventory events.

### 4.4 Returns and condition
Build 017 supplies an authorized disposition such as restock, quarantine, repair, or write-off request. Inventory records only the approved stock effects and retains the disposition reference. No returned item becomes sellable solely because it was physically received.

### 4.5 Acquisition and per-item cost
Acquisition supplies receipt and item-level landed-cost allocations. Inventory preserves the relevant cost reference or approved cost snapshot according to accounting policy. Do not divide a pallet cost equally across unlike products unless the approved allocation method explicitly requires it.

### 4.6 Shipping and pickup
Fulfillment requests picks against valid reservations. Dispatch and pickup confirmation must reference the order, reservation, location, and item/quantity scope. Failed handoff creates an exception; it must not silently release or reassign stock.

### 4.7 Analytics
Analytics consumes events or controlled read models. Exports must be permission-scoped and minimize serial/IMEI exposure. Dashboard totals must identify their data timestamp and reconciliation status.

## 5. Canonical identifiers and correlation

Use stable opaque identifiers for:
- product and SKU;
- inventory unit and quantity lot;
- location;
- acquisition receipt and receipt line;
- movement;
- reservation and reservation line;
- order and order line;
- transfer;
- inspection and disposition;
- event and automation execution.

Every cross-build request should carry a correlation ID and idempotency key where a command can create a side effect. Do not use serial number, IMEI, email address, or other personal/sensitive values as a correlation key.

## 6. Security and trust boundaries

- Authenticate service-to-service requests using approved server-side credentials or workload identity.
- Authorize each command by actor, role, permission, and location scope.
- Keep secrets in the approved secret manager/environment configuration; never commit them to GitHub or expose them to browser code.
- Validate payload schema, size, enum values, and referenced entity ownership.
- Apply rate limits and replay protection to external ingress.
- Sign or otherwise authenticate outbound webhooks where supported.
- Redact protected identifiers and personal data from logs, traces, and alerts.
- Use separate credentials and least-privilege scopes per integration.
- Revoke and rotate credentials through a documented incident process.
- Treat all external payloads and user-provided CSV fields as untrusted data.

## 7. Reliability and consistency

- Use transactional outbox for events emitted from inventory transactions.
- Use consumer inbox/deduplication records or equivalent idempotent processing.
- Apply bounded retries with backoff and dead-letter review.
- Preserve event IDs and schema versions during replay.
- Handle out-of-order events by checking authoritative state/version.
- Reconcile order, reservation, movement, and fulfillment references on a schedule.
- Make integration lag, failure rates, and last-success timestamps observable.
- Never resolve a mismatch by directly overwriting the movement ledger.

## 8. Integration rollout sequence

1. Confirm ownership and contract for each connected build.
2. Verify actual repository routes, services, schema, and existing integration code when inspection is authorized.
3. Implement Inventory Core foundation and security controls.
4. Implement internal command interfaces and outbox.
5. Integrate one non-production consumer at a time.
6. Test duplicates, replay, out-of-order delivery, timeout, partial failure, and reconciliation.
7. Pilot with synthetic data and controlled staff access.
8. Approve production credentials, monitoring, rollback, and operational ownership before release.

The previously paused database preflight remains paused. This document does not authorize further database inspection.

## 9. Acceptance criteria

- [ ] Every integration has a named data owner and explicit authority boundary.
- [ ] No connected build writes inventory balances directly.
- [ ] Commands validate actor, permission, and location scope server-side.
- [ ] Commands that create side effects support idempotency.
- [ ] Events are versioned, minimal, and delivered through a recoverable mechanism.
- [ ] Consumers tolerate duplicates and out-of-order delivery.
- [ ] Availability projections are labeled as non-authoritative.
- [ ] Payment, pricing, identity, returns, fulfillment, and accounting remain in their owning domains.
- [ ] Sensitive identifiers and secrets are not exposed in payloads or logs.
- [ ] Reconciliation and failure ownership are documented.
- [ ] Non-production integration tests pass before any production connection.

## 10. Completion boundary and next gate

This is a design document only. No APIs, adapters, webhooks, credentials, database changes, UI, tests, or deployments were created or executed. No database inspection was performed.

**Next gate:** Approve the cross-build ownership matrix and prioritize the first non-production integration. Build 004 application-side identity/session integration remains unverified; it must be completed and tested before inventory commands rely on it for production authorization.
