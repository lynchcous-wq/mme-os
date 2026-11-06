# Build 001 — Checkout Recovery & Abandoned Cart Intelligence

**Status:** Proposed additive migration; not applied.

Adds saved cart sessions, cart items and recovery attribution events. Cart rows do not reserve stock and do not guarantee price or availability. On checkout restoration, the trusted checkout service must reload current product prices, verify condition and active status, confirm location availability and create a fresh order/reservation through the existing atomic checkout path.

The abandonment worker marks idle active carts abandoned (default 60 minutes; configurable 15 minutes to 7 days) using SKIP LOCKED. It does not send a message or reserve/release inventory. Recovery tokens are stored as SHA-256 digests, expire within 72 hours, and may be issued only for signed-in customer carts with explicit recorded marketing consent. Guest carts are not eligible for proactive recovery messaging in this initial scope.

Successful token validation restores the cart state but does not create an order, charge a payment method or reserve inventory. Checkout conversion attribution must be recorded by the trusted order service. Marketing contact preferences, channel-specific consent, unsubscribe/suppression, rate limits and data retention must be enforced by the notification service before sending any reminder.

All tables and RPCs are service-role only. The backend must bind cart access to the authenticated customer or verified guest session; cart IDs and hash parameters are not authentication. Recovery tokens must be generated with a cryptographically secure random generator and never logged.

Verification scenarios: abandoned threshold, repeated worker execution, guest/no-consent token denial, expired and wrong token rejection, token single use, restored cart requiring fresh price/stock checks, and confirmation that cart writes do not modify inventory reservations.