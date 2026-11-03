# Build 001 — reservation lifecycle and payment reconciliation

**Status:** Proposed additive migration only. Not applied. Stripe is not connected; checkout remains disabled.

## Added lifecycle operations
- `mme_release_order_reservation` releases active stock holds and moves pending orders to payment_failed, cancelled, or expired. Balance invariants are checked.
- `mme_expire_inventory_reservations` is a bounded 1–1,000 row worker using SKIP LOCKED to support concurrent schedulers.
- `mme_process_verified_payment_event` deduplicates Stripe event IDs, checks exact USD amount against the order, releases stock on failed payment, and consumes stock only for a still-active, unexpired reservation after payment success.

## Trusted-server requirements
The server adapter must verify the Stripe webhook signature against the raw body, match PaymentIntent ID and order metadata, enforce expected test/live mode and account context, and only then call the payment RPC. The RPC is not a substitute for Stripe signature verification. Never expose service_role or webhook secrets to a browser.

Late success after reservation expiry returns `reservation_expired_refund_review`; amount mismatch returns `amount_or_currency_mismatch`. Both require a human/automated refund-review workflow. This migration does not issue refunds or call Stripe.

## Operational gates
1. Apply in a disposable Supabase development project only after Build 004 identity migrations are reviewed and ordered.
2. Run pgTAP and real PostgreSQL integration tests, including last-unit concurrency and multi-line rollback.
3. Test expiry, failure, success, amount mismatch, late success, and duplicate delivery.
4. Implement signed webhook verification in the trusted server adapter.
5. Keep serialized inventory unavailable for online checkout until IMEI/serial-level unit reservation exists.
6. Keep customer checkout disabled until Stripe test mode, reconciliation, refunds, and alerts pass.
