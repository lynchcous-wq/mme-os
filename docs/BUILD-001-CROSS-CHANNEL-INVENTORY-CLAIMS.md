# Build 001 — Cross-Channel Inventory Claims & Available-to-Sell

**Status:** Additive migration committed; not applied.

Adds a shared temporary claim ledger for customer holds, POS quotes, subscription allocations, auctions and authorized manual allocations. Claims support aggregate stock and individual serialized units. Aggregate claims increment the same inventory balance reserved quantity used by website order reservations; serialized claims transition a unique in-stock unit to reserved. Both paths lock their stock rows to prevent concurrent double allocation.

Claims require a source reference, creator identity, explicit expiry and valid product/location quantities. Claims expire no later than 30 days after creation. Release is idempotent and restores aggregate reserved quantity or serialized in-stock status, while protecting serialized units that still have an active website-order reservation. A bounded expiry worker uses SKIP LOCKED for safe concurrent processing.

The available-to-sell view combines aggregate balances and serialized units. It is service-role-only. This migration does not mark a claim as sold, take payment, or convert a claim into an order; those operations must use an explicit atomic conversion workflow before channel checkout is enabled. Existing website checkout and Stripe payment handling are unchanged. UUID identity values are attribution only; trusted server-side authentication and role authorization remain mandatory.