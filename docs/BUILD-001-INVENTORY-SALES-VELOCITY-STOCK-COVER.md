# Build 001 — Inventory Sales Velocity & Stock Cover

**Status:** Additive migration committed; not applied.

Adds a location-level view for active, non-serialized products. It reports paid units and line revenue over rolling 30-, 60- and 90-day windows, current on-hand/reserved/available quantities, 30-day average daily unit sales, estimated days of available stock at that recent rate, and 30-day captured COGS with a missing-cost count.

The view uses order-line creation time because the current order schema does not expose a dedicated immutable paid-at timestamp. It filters to orders currently marked paid. It is a management indicator, not an accounting sell-through cohort or guaranteed stockout forecast. Revenue excludes order-level discounts, refunds, tax, fees and overhead; missing cost snapshots are disclosed rather than treated as zero. Serialized devices remain in their separate per-unit reporting workflow.

Access is service-role only; the application server must enforce MME role and location scope.