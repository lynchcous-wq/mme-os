# Build 009.42 — Stripe refund adapter and webhook

Implementation branch only. Provider requests are server-side, authenticated and idempotent. Stripe webhook signatures must be verified against the raw request body with a bounded timestamp tolerance. Deduplicate provider event IDs, match connected account, payment intent, refund ID, amount and currency, and reconcile uncertain outcomes before retry. Never store PAN, CVV or PIN. Production enablement requires tests, migration replay and Stripe sandbox verification.

Status: implementation in progress; not deployed.