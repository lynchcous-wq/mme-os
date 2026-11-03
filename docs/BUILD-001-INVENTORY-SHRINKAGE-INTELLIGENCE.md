# Build 001 — Inventory Loss Prevention & Shrinkage Intelligence

**Status:** Additive migration committed; not applied.

Adds a normalized, source-linked signal ledger for cycle-count variances, receiving variances, inventory adjustments, damage/return inspections, POS voids/refunds and serialized-unit mismatches. A source type + source ID is unique so retries do not create duplicate signals. Evidence is structured JSON with a 16 KB cap. Signals carry severity, location, product, quantity delta and optional estimated loss value.

A 30-day pattern view groups repeated signals by location and product and requires at least two signals. It reports counts, source diversity, severity and estimated loss. A recurring signal is an investigation lead only; it is not a finding of employee misconduct or fraud.

Authorized management review can mark a signal reviewed or dismissed with a required note. This ledger does not adjust stock, issue refunds, accuse individuals or automatically discipline employees. Existing inventory exception management remains the case workflow; trusted services must link signals to exceptions and enforce MME role/location access before exposing any data.