# Build 001 — Customer Fulfillment Notifications & Pickup Verification

**Status:** Proposed additive migration; not applied.

## Customer notifications
An idempotent outbox queues order-paid, picking, shipped, pickup-ready, pickup-reminder, delivered, picked-up and exception notices over email or SMS. A trusted worker sends through configured providers and records provider delivery outcomes. This migration does not itself send messages or configure provider credentials.

## Secure pickup verification
A trusted backend generates a cryptographically random one-time code and sends it to the verified customer contact. Only the SHA-256 digest is stored. Challenges expire within 24 hours, have a maximum of five attempts by default, and are single-use. Issuing a replacement revokes prior outstanding challenges.

A successful code check records a verification event but does not mark the order picked up. Staff must separately complete the handoff through the existing fulfillment transition and attach the required proof digest. Never log or store raw pickup codes, identity documents, or payment credentials.

## Security and operational requirements
All tables and RPCs are service-role only. The backend must authenticate staff, authorize store/location scope, rate-limit verification attempts by order/customer/device/network, and use a cryptographically secure random generator. A hash alone does not replace rate limiting or staff verification. Notification workers must retry safely and honor customer contact preferences and applicable consent/opt-out requirements.

## Verification
Run disposable database integration tests for duplicate notification idempotency, wrong fulfillment/order association, pickup-only challenge issuance, non-ready pickup rejection, expired code, wrong code attempt limits, single-use consumption, replacement-code revocation, and ensuring code verification does not transition fulfillment to picked_up.