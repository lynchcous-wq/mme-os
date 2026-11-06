# Build 001 — POS PaymentIntent Binding Hardening

**Status:** Proposed additive migration; not applied.

Every Stripe PaymentIntent success/failure event must now reference an exact server-created PaymentIntent binding for the same MME order. A database trigger enforces this invariant for both aggregate and serialized checkout processors before an event can enter the payment event ledger.

This closes a gap where the serialized payment processor accepted a provider object ID without checking that it was the PaymentIntent originally created for that order.

The trusted webhook adapter must still verify Stripe's signature, endpoint/account, live/test mode, event type and payload. Payment processing must continue to verify the received amount and currency against the order and the binding. This database guard does not replace webhook signature verification or perform a payment itself.

## Verification
The pgTAP test checks guard function and trigger installation plus restricted direct execution. Integration tests must additionally prove that a correctly bound event succeeds, an unbound PaymentIntent is rejected, and a PaymentIntent bound to another order is rejected for both checkout types.