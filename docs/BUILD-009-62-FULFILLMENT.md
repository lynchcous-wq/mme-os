# Build 009.62 — Enterprise Order Fulfillment & Shipping Orchestration

## Scope
Normalize website, POS, subscription, auction, shipping and local-pickup orders into a fulfillment workflow tied to Build 009.61 reservations.

## Lifecycle
Order intake -> active reservation attachment -> payment confirmation/stock commitment -> pick -> pack -> label/tracking -> carrier handoff -> delivery; or verified pickup. Exceptions stop normal progress pending investigation.

## Inventory and payment boundary
An order line must reference an active reservation whose order reference and location match the fulfillment order. Payment confirmation consumes each reservation through the Build 009.61 RPC and posts inventory sale ledger entries. This RPC must only be called after the trusted payment service verifies settled/authorized capture according to MME's payment policy; never trust a browser-supplied paid flag. Fulfillment dispatch itself does not decrement stock a second time.

## Warehouse operations
Picking is quantity bounded by ordered quantity. Packing is bounded by picked quantity. Package records capture dimensions, weight, label and tracking references. This schema records label/carrier metadata; it does not itself purchase postage or call carrier APIs.

## Shipping
Carrier events are accepted only when the tracking reference matches the order. Supported normalized events: accepted, in transit, out for delivery, delivered and delivery failed. Failed delivery creates an investigation exception. Provider webhooks must be authenticated, signature-verified, replay-protected and normalized by a trusted integration adapter.

## Local pickup
Pickup requires a hash of a one-time code and an expiry. Confirmation compares hashes and clears the stored hash after successful pickup. Generate codes using a cryptographically secure random source and store only a keyed hash; do not log or expose raw codes. Verify customer identity at handoff.

## Security
RLS enabled; browser roles have no direct table access. All mutations use service-role RPCs behind trusted APIs with actor, role, location, order ownership and state authorization. Events are append-only. Restrict PII access and retention; encrypt sensitive recipient/address data at rest and in transit.

## Validation
Run `npm run lint`, `npm run test:build009:fulfillment`, and prior Build 009.53–009.61 suites. PostgreSQL integration tests should cover idempotent order intake, duplicate payment callbacks, reservation expiry during checkout, partial picks, packing, package labels, webhook replay/signature validation, wrong tracking IDs, pickup code replay/expiry and exception resolution.

## Rollout boundary
Draft implementation only. No carrier API or label purchase, customer notification provider, live POS/website sync, barcode scanner interface, route optimization, production migration replay or deployment is claimed.
