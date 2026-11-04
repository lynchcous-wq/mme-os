# Build 001 — Competitive Market Pricing Intelligence

**Status:** Additive migration committed; not applied.

Adds a sourced competitor observation ledger. Each observation records the MME product, condition, observed price, seller, source URL, listing reference, confidence, observation timestamp and source type. New observations remain pending until independently verified by a different identity.

The market-position view compares only verified, condition-matched observations with at least 90% match confidence and age no more than 90 days. It reports median, low and high comparable prices, sample size, latest observation, 30-day sample count and MME's percentage difference from the median. It flags evidence older than 30 days and samples with fewer than three comparables.

This migration does not scrape websites or establish a live feed. A future approved provider/import integration must supply observations and preserve source provenance. External prices are not verified facts until reviewed. Market comparisons do not modify MME pricing; existing CEO-authorized markdown approval remains separate.