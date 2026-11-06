# Build 009.61 — Inventory Reservation & Allocation Engine

## Purpose
Provide atomic stock holds for POS, website, local pickup, shipping, subscription, staff and auction channels. A reservation reduces available-to-promise quantity but does not remove physical on-hand inventory.

## Lifecycle
Reserve -> active hold with expiry -> consume on confirmed sale, or release/cancel/expire. Reservation events are append-only. Expiration is processed in bounded batches with SKIP LOCKED for concurrent workers.

## Concurrency and idempotency
Reservation serializes by SKU/location/currency advisory lock and locks the balance row before checking available stock. Unique idempotency keys prevent duplicate holds; payload mismatch is rejected. Reservation TTL is capped at seven days. Consumption is a separate idempotent operation that posts the sale movement and decreases both on-hand and reserved quantities.

## Allocation channels
Supported channels are POS, website, local pickup, shipping, subscription, staff and auction. Priority classes are metadata only in this build; no priority class may bypass stock availability or reservation locks. Customer/member eligibility and allocation policy must be enforced by the trusted application API before calling the RPC.

## Expiry and release
Release and expiry decrement reserved quantity only; they do not write physical inventory ledger movements. Expiry worker processes at most 1,000 rows per call and uses SKIP LOCKED. An external scheduler/worker must invoke it.

## Availability
The service-role view exposes on-hand, reserved and available quantities for trusted channel adapters. Public website APIs must expose only appropriately scoped, cached/synchronized availability; do not expose internal costs or unrestricted location data.

## Security
RLS enabled; no browser-role direct table access. All RPCs are service-role only. Trusted API must authenticate actor, authorize location/channel/customer, validate order ownership and apply payment/checkout state gates. Service role credentials must never reach clients.

## Validation
Run `npm run lint`, `npm run test:build009:reservations`, and prior Build 009.53–009.60 suites. PostgreSQL integration tests must cover simultaneous reservations, retries, expired holds, cancellation, sale consumption, multi-currency separation and reserved/on-hand invariants.

## Rollout boundary
Draft implementation only. No scheduler deployment, website/POS integration, payment authorization, customer-facing availability endpoint, priority policy enforcement or production migration replay is claimed.
