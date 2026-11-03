# Build 001 — serialized checkout lifecycle

**Status:** Proposed additive migration. Not applied. Checkout is not enabled.

A dedicated single-device order path now:
- Locks one physical serialized unit and verifies it is in stock.
- Creates a pending order, snapshots price, condition, serial and IMEI, and reserves that exact unit.
- Releases the unit on failed payment, cancellation, or expiry.
- Marks the unit sold only after a server-verified Stripe success event with exact USD amount.
- Uses the shared unique Stripe event ledger for duplicate-delivery protection.

The existing aggregate checkout RPC continues rejecting serialized products. This first implementation intentionally supports one serialized unit per order; multi-unit serialized carts require a later atomic batch path.

The trusted server must verify Stripe's raw-body signature, PaymentIntent/order association, account and test/live mode before calling the serialized payment RPC. Late success or amount mismatch is routed to refund review; this SQL does not issue refunds. IMEI and serial data must not appear in public catalog payloads.

Test in disposable PostgreSQL after migrations 006, 007 and 008. Include concurrent attempts to reserve the same unit, expiry/payment race, failed payment release, successful consume, duplicate event, and amount mismatch.
