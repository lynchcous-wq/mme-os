# Build 009.41 — Serialized Return Refund & Payment Provider Reconciliation

Status: implementation committed to review branch. CI and database validation pending. Not deployed.

## Objective
Connect a resolved serialized customer return to the existing Build 009.12 refund request, independent approval, durable provider dispatch, trusted provider outcome and Build 009.13 settlement reconciliation.

## Implementation
- Additive migration: `supabase/migrations/20261105001210_build009_serialized_return_refund_reconciliation.sql`.
- One-to-one link between an inspected serialized return, one existing POS refund request and its captured tender attempt.
- Refund preparation requires a resolved return inspection and the full serialized order-line amount. Partial or adjusted line refunds are sent to manual handling rather than being incorrectly labelled fully refunded.
- Automated refund path requires exactly one eligible captured/partially-refunded tender with sufficient remaining captured balance. Split tender, missing tender, or insufficient single-tender balance is routed to manual review.
- Existing Build 009.12 refund request RPC enforces staff authorization, idempotency, tender remaining balance and separate approver.
- Existing Build 009.12 dispatch worker provides durable queue claims, bounded leases, idempotency key, retries and trusted provider outcome recording.
- Provider completion synchronizes the serialized return to `status=refunded` and `refund_status=confirmed` only when refund request type, provider operation reference, provider refund reference, amount and currency match the linked request.
- Failed and unknown outcomes move the return to manual review; they do not mark the return refunded or automatically issue another refund.
- Settlement reconciliation remains a separate status from immediate provider confirmation. A later settlement mismatch is recorded as an exception without falsely reversing the fact that the provider confirmed the customer refund.
- Append-only-style return refund event history records request, approval, dispatch, outcome and settlement state changes.
- Browser roles receive no direct table or function access; service role is the trusted server boundary.

## Existing dependencies reused
- Build 009.12: `mme_pos_refund_requests`, `mme_pos_request_refund_or_void`, `mme_pos_decide_refund_request`, `mme_pos_claim_refund_dispatch`, `mme_pos_finish_refund_dispatch`.
- Build 009.13: `mme_pos_reconcile_refund_settlement`.
- Build 009.40: `mme_serialized_return_requests`, return inspection resolution and refund status.
- Existing tender attempt ledger and transaction orchestration.

## Provider boundary
This migration does not call Stripe, Verifone or another processor. A trusted server-side provider adapter must claim approved requests, send the provider refund with the persisted idempotency key, verify provider response/webhook evidence, and call the existing finish RPC with the real provider references. An unknown result must be reconciled against the provider before any retry. Never place PAN, CVV, PIN or raw card data in this workflow.

## Operational constraints
- No automated split-tender allocation in this version.
- No automatic partial refund, restocking fee or manual amount adjustment in this version.
- A failed refund is not silently retried by creating a second request; it is escalated for provider verification and authorized resolution.
- Return completion means the provider-confirmed refund was recorded; settlement matching is separately tracked.
- The store/customer return UI and customer notifications are not included in this database integration.

## Validation
- `npm run lint`
- `npm run test:build009:serialized-return-refunds`
- `npm run test:build009:serialized-returns-warranty`
- `npm run test:build009:serialized-checkout-cogs`
- `npm run test:build009:inventory-cogs`
- Fresh Supabase migration replay, PostgreSQL integration tests and provider sandbox tests remain required before merge or live use.

## Rollout
Keep production refund dispatch disabled until a provider adapter is configured and sandbox-verified. Review the PR, run migration replay against a disposable database, verify provider idempotency and webhook signature validation, and obtain approval before deployment.
