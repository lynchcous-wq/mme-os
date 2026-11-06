# Build 009.52 — Enterprise Customer Order Tracking & Self-Service Portal

## Scope
Create the authenticated customer order portal read model and safe self-service request foundation. This is a projection layer; it does not replace the authoritative order, payment, shipping, returns, refund, warranty or subscription domains.

## Customer experience
- Order history with order reference, date, status, currency and total.
- Shipment carrier, tracking number, HTTPS tracking link and estimated delivery.
- Local pickup readiness, pickup location and collection timestamps.
- Refund status and amount.
- Warranty status and expiration.
- Subscription status and renewal-period end.
- Submit cancellation requests for eligible unshipped orders.
- Submit return requests for eligible fulfilled orders.
- View submitted service-request status.

## Identity and access
An explicit mapping binds Supabase Auth `auth.uid()` to one active MME person identity. Linking is performed only by a trusted service-role identity verification workflow. Customer read policies use the authenticated subject and active link; clients cannot supply or override person_id. Revoking/suspending the link immediately removes portal access.

## Data flow
Trusted commerce adapters maintain customer-safe order and fulfillment projections through service-role RPCs. Refund, warranty and subscription projections are reserved for their authoritative domain adapters. The portal never accepts payment-card credentials, provider secrets or arbitrary tracking URLs; tracking links must be HTTPS and should be validated against carrier allowlists in the adapter.

## Service requests
Cancellation requests are rejected for shipped/delivered/completed/cancelled/refunded orders. Return requests require a delivered/completed/partially shipped state and remain subject to staff review, item condition, serial-number checks and the MME returns policy. Submission is a request only; it does not itself cancel an order, issue a refund, create a return label or alter inventory. One open request per order and request type is allowed.

## Security
- RLS on all seven portal tables.
- Authenticated users receive read-only access, scoped by active auth-to-person link.
- Trusted service role owns account provisioning and order/fulfillment projection writes.
- Customer request RPC derives person identity from auth.uid() and validates order ownership.
- No direct client writes to order or fulfillment status.
- Do not expose internal notes, payment instrument data, full address, employee-only records or fraud/risk details.

## Integration still required
Connect account verification to the MME identity service; connect order/payment/fulfillment/returns/refunds/warranty/subscription domain adapters; implement customer UI and API routes; add tracking-carrier allowlists, item-level return eligibility, pickup verification and notification links; provide staff review and audit workflows.

## Validation
Run `npm run lint` and `npm run test:build009:customer-order-portal`. PostgreSQL integration tests must cover cross-account reads, suspended links, revoked links, auth.uid spoofing attempts, order ownership, duplicate requests, cancellation/return eligibility, projection upserts, and service-role boundary.

## Rollout boundary
Implementation branch only. This migration does not create a live website screen, connect live commerce tables, verify identity documents, issue cancellations/refunds, or activate production tracking integrations.
