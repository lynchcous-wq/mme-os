# Build 001 — order and payment readiness specification

**Status:** Architecture specification only; no payment code or live connection  
**Provider:** Existing MME Stripe account, test mode first  
**Storefront:** Much More Electronics, `www.muchmoreelectronics.com`

## 1. Non-negotiable payment boundary

The current catalog and browser-local demo bag are not connected to an order database. They cannot accept payment. Do not expose a live checkout button or create a Stripe PaymentIntent/Checkout Session until the prerequisites in this document are implemented and tested.

Stripe secret keys and webhook signing secrets must exist only in encrypted server-side environment secrets. Never place them in browser code, repository files, logs, or chat. Use Stripe test keys and a test webhook secret in development.

## 2. Required authoritative records

- Product and variant records with immutable SKU identifiers.
- Condition grade and inspection status for used/refurbished devices.
- Serialized inventory for IMEI/serial-tracked devices.
- Location-aware stock ledger and reservation records.
- CEO-approved current price and tax classification.
- Customer identity reference, with no raw payment card data stored by MME.
- Order, order line, fulfillment choice, payment attempt, refund, and webhook event records.
- Append-only audit trail for price overrides, inventory adjustments, order status changes, refunds, and privileged actions.

Client-submitted prices, product titles, stock quantities, discounts, and totals are untrusted. Recalculate all totals on the server from approved catalog and pricing records.

## 3. Checkout lifecycle

1. Customer signs in or uses an explicitly approved guest checkout flow.
2. Server validates every cart item, price, condition, availability, quantity, and fulfillment eligibility.
3. Server calculates subtotal, discounts, tax, shipping/pickup charges, and final total.
4. Server creates a pending order and time-limited inventory reservation in one database transaction.
5. Server creates a Stripe Checkout Session using the server-calculated total and internal order ID in metadata.
6. Browser is redirected to Stripe-hosted checkout. MME does not collect or store card numbers or CVC.
7. Stripe sends a signed webhook to the MME endpoint.
8. Endpoint verifies the signature against the raw request body before processing.
9. A unique Stripe event ID is persisted under a unique constraint. Duplicate events are acknowledged without repeating side effects.
10. A valid payment event transitions the order to paid only after server-side verification and amount/currency/order matching.
11. Fulfillment is released only from the authoritative paid order state.
12. Failed, expired, canceled, disputed, and refunded paths are separately represented and audited.

The browser success URL is informational only. It must never be treated as proof of payment.

## 4. Idempotency and concurrency

- Require an idempotency key for order creation and Stripe session creation.
- Enforce unique provider event IDs and provider payment/session IDs in the database.
- Lock or atomically reserve inventory to prevent overselling when two customers attempt to buy the same serialized unit.
- Never decrement stock from a browser redirect or unverified webhook.
- Expire reservations safely and release stock only after checking payment/session state.
- Use retry-safe webhook processing and a reconciliation job for delayed, missing, or out-of-order events.

## 5. Shipping and local pickup

Each order must store the selected fulfillment method and a snapshot of the applicable address or pickup location. Pickup orders require a fulfillment status workflow, identity/authorization check at handoff, and proof-of-release record. Shipping orders require validated destination, carrier/service selection, label/tracking records, and shipment status events. Shipping rates, tax, and delivery promises must come from configured services/rules—not hardcoded guesses.

## 6. Reconciliation and operations

Provide an authorized Payments Center view for:
- Orders awaiting payment, paid, failed, expired, partially refunded, refunded, and disputed.
- Stripe session/payment identifiers and event history.
- MME order total versus Stripe amount/currency.
- Duplicate or unprocessed webhook events.
- Daily payout and transaction reconciliation.
- Refund approvals and immutable audit events.

No reconciliation screen may expose secret keys or full payment credentials.

## 7. Test plan before enabling payments

- Successful test-mode payment.
- Declined/failed payment.
- Customer abandons or expires checkout.
- Webhook signature invalid or missing.
- Duplicate webhook delivery.
- Webhooks delivered out of order.
- Network retry after order/session creation.
- Cart price changed between browse and checkout.
- Two customers competing for one serialized device.
- Tax/shipping/pickup calculations and address validation.
- Full and partial refund paths.
- Stripe dashboard transactions reconciled to MME order records.

## 8. Release gates

Production payments remain disabled until:
- Build 004 identity and authorization boundaries are reviewed and migrated in a dedicated development project.
- Database schema, migrations, backups, and server-only service-role access are validated.
- All payment and inventory tests pass in a disposable test environment.
- Stripe test-mode end-to-end flow and webhook delivery are demonstrated.
- Reconciliation and refund permissions are approved.
- Production secrets are configured directly by an authorized operator in encrypted deployment settings.
- CEO explicitly approves production activation.

## Current status

No Supabase project is connected, no order database exists, and Stripe is not connected to this repository. This document is a build specification, not evidence that checkout or payment processing is implemented.
