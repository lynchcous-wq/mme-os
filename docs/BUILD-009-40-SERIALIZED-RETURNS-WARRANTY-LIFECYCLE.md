# Build 009.40 — Serialized Returns, Warranty & Condition Lifecycle

Status: implementation committed to a review branch. TypeScript and contract validation pending CI. Production rollout is not authorized.

## Objective
Complete the post-sale lifecycle for serialized electronics by connecting customer return intake and warranty claims to Build 001 inspections, Build 009.38 cost-bearing serial units, immutable inventory movements and condition-grade disposition.

## Delivered
- Additive migration: `supabase/migrations/20261105001200_build009_serialized_returns_warranty_lifecycle.sql`.
- Store-specific serialized return policy table. Policies are disabled until explicitly configured; return-window days are configurable rather than silently assumed.
- Customer return request records tied to the original paid order line, serialized unit, customer identity and store.
- Idempotent return requests, one open return per order line, and store policy / customer ownership / return-window checks.
- Employee-authorized return intake using the existing Build 001 atomic inspection submission and device-test workflow.
- Separate resolver and approver authorization for return disposition.
- Serialized warranty registration storing the provider, plan, supplied terms snapshot, contract reference and exact start/expiry dates.
- Warranty claim intake with customer ownership, active-coverage checks and idempotency.
- Warranty claim inspection intake using existing Build 001 inspection workflow.
- Inspection trigger synchronizes legacy serialized-unit status with the Build 009 cost unit and aggregate stock balance.
- Available units entering inspection are removed from aggregate on-hand inventory; sold units are not decremented a second time.
- Return-to-stock restores one unit with the recorded actual cost and updates weighted-average cost. Write-off and supplier-return dispositions retire the cost unit from available inventory.
- Inspection and disposition events are appended to the cost-ledger event history; original sale-time COGS snapshots remain immutable.
- Contract suite: `tests/build009-serialized-returns-warranty-lifecycle.test.mjs`.
- CI workflow: `.github/workflows/build009-serialized-returns-warranty.yml`.

## Refund boundary
A return inspection is not proof that a refund was issued. This build does not call Stripe or any payment provider and does not mark a return refunded. The return record remains at inspection resolution until a separate trusted provider-refund outcome is reconciled. This avoids promising a customer money back before the processor confirms it.

## Warranty boundary
Warranty terms and expiry dates must be supplied from the actual warranty agreement. No default warranty duration or coverage is invented. Warranty claims are recorded and routed through inspection; provider reimbursement, replacement authorization and claim settlement remain external/next-stage workflows.

## Security and integrity
- Return policies, requests, warranties and claims use RLS with browser-role access revoked; service-role access only.
- Customer return and warranty requests must match the paid order's customer identity.
- Return windows require an enabled store policy and a configured number of days.
- Inspection intake uses existing employee permission and store/product scope checks.
- Return resolution requires separate authorized resolver and approver identities.
- Serial cost units without a matching cost ledger cannot be restored to sellable stock automatically.
- Actual unit acquisition cost is retained through return-to-stock; original sale COGS is never rewritten.
- Customer-facing refunds remain pending until a separately verified provider result is recorded.

## Validation
- `npm run lint`
- `npm run test:build009:serialized-returns-warranty`
- `npm run test:build009:serialized-checkout-cogs`
- `npm run test:build009:inventory-cogs`
- Fresh Supabase migration replay and PostgreSQL tests remain required before merge. The Build 009.39 GitHub runner failed while starting the isolated Supabase stack before migration replay; this was an environment/setup failure, not a passing database validation.

## Rollout
Configure and approve store return policies and warranty terms before enabling customer workflows. Merge only after CI, SQL replay and integration tests succeed. No live customer returns, payment refunds, warranty-provider calls or website deployment are claimed.
