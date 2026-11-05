# Build 009.44 — Stripe Refund Settlement Reconciliation

## Purpose
Connect completed Stripe refund requests to the exact Stripe refund balance transaction imported into an MME payout batch. Record the settlement match, mirror the result to the serialized return workflow, and post an attributable refund fact to MME financial reporting.

## Controls
- Only a provider-confirmed completed refund can be reconciled.
- Require exact Stripe refund ID, Stripe connected-account reference, refund line type, currency and absolute amount.
- Prevent a refund request or settlement line from being matched twice.
- Preserve mismatches and ambiguous/cross-match conditions as explicit review outcomes.
- Update the existing refund request's provider reconciliation status; Build 009.41's trigger mirrors settlement status into the serialized return record.
- Post a negative integer-minor-unit financial refund fact through the existing append-only financial fact import RPC.
- Reuse the existing source idempotency key based on the Stripe refund reference. Conflicting duplicate source content is never overwritten.
- If the relevant financial period is closed, preserve the settlement match but mark the fact as period_closed; use the authorized financial adjustment/reopen workflow.
- CEO/Finance reporting exposes counts and amounts by store, connected account and currency. It does not claim that a Stripe payout equals a bank deposit.
- No provider calls, refunds, ACH, wire, payout or bank movement are initiated by this build.

## RPC
`mme_pos_match_stripe_refund_settlement_line(refund_request_id, settlement_line_id, actor_person_id, business_date, business_timezone)`

The actor must hold the existing store-scoped `pos.settlement.reconcile` permission. Business date must agree with the confirmed refund timestamp in the supplied IANA timezone.

## Dashboard
The service-role view `mme_pos_stripe_refund_settlement_dashboard` reports matched, mismatched, manual-review and closed-period counts and amounts by location, Stripe connected account and currency. Existing financial reporting includes the matched refund as a negative `refund` fact. Bank deposit confirmation remains a separate Build 009.30 workflow.

## Validation required
- `npm run lint`
- `npm run test:build009:stripe-refund-settlement`
- Existing `npm run test:build009:stripe-refunds`, `npm run test:build009:serialized-return-refunds`, `npm run test:build009:settlement-integrity`, and `npm run test:build009:financial-reporting`
- Fresh ordered Supabase migration replay and PostgreSQL integration tests for exact match, duplicate match, connected-account mismatch, currency/amount mismatch, duplicate line, closed period, conflicting financial fact, return trigger propagation, and independent bank deposit match.

## Rollout boundary
Implementation branch only. No migration has been applied to production, no Stripe settlement file has been imported, and no live financial dashboard deployment is claimed.
