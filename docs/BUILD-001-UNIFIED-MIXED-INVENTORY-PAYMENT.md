# Build 001 — Unified Mixed-Inventory Payment Processing

**Status:** Additive migration committed; not applied.

Adds one service-role-only Stripe PaymentIntent event processor for orders containing aggregate inventory, serialized devices, or both. It verifies the exact server-bound PaymentIntent and expected amount, deduplicates provider event IDs, locks the order and reservation, and consumes all aggregate balances and serialized units in one database transaction. A failed payment releases both reservation types together. A late success after reservation expiry releases the stock and returns an explicit refund-review result; it never marks the order paid.

The trusted webhook adapter must verify Stripe signature, connected account, live/test mode and event payload before calling this RPC. This database function does not contact Stripe, create PaymentIntents, or itself prove webhook authenticity. Existing specialized processors remain available for backward compatibility; the server must route a given order to exactly one processor, preferably this unified function for all new orders.