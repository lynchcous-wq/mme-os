# Build 001 — Unified Reservation Expiration

**Status:** Additive correction; migration committed, not applied.

The existing checkout reservation window is capped at 30 minutes. This correction makes the expiry worker inspect order lines and invoke the matching release workflow:

- Aggregate products: decrement reserved quantities on inventory balance rows and release the reservation.
- Serialized products: return the individually reserved device to in-stock, release the serialized reservation line and release the parent reservation.

The worker still processes only pending-payment orders whose active reservation expiry is due. It uses SKIP LOCKED to avoid orders concurrently locked by checkout/payment processing, and retains the bounded batch size of 1–1,000. Expiration remains service-role only.

This migration does not extend or silently change the 30-minute checkout window, does not expire paid orders, and does not alter Stripe payment reconciliation. A late successful payment for an expired reservation remains a refund-review exception; the payment webhook must not consume unavailable stock.

Run the SQL test and disposable-database integration scenarios for both aggregate and serialized orders. Verify aggregate reserved_quantity returns to its prior value, serialized unit_status returns to in_stock, reservation statuses become expired, duplicate worker runs are harmless, and a concurrent successful payment cannot be expired or consumed twice.