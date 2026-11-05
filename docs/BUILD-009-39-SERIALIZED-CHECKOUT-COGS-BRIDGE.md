# Build 009.39 — Serialized Customer Checkout & Sale-Time COGS Bridge

Status: implementation committed to a review branch. Contract tests and fresh Supabase migration replay are required before merge; production rollout is not authorized by this change.

## Objective
Connect the existing Build 001 single-unit serialized customer checkout and verified Stripe payment lifecycle to the Build 009.38 actual-cost inventory ledger. A serialized item must have one physical unit identity, one cost-bearing ledger unit, one active reservation, one verified payment outcome, and one immutable sale-time cost snapshot.

## Delivered
- Additive migration: `supabase/migrations/20261105001190_build009_serialized_checkout_cogs_bridge.sql`.
- Checkout-ready receiving wrapper creates the legacy Build 001 serial identity and the Build 009.38 cost unit in one database transaction, then links them by serial/IMEI digest.
- Order-line insertion requires a matching available cost-bearing unit and reserves one aggregate inventory unit.
- Existing Build 001 release/expiry transitions release the linked cost-unit reservation and decrement aggregate reserved quantity.
- Existing verified Stripe success flow transitions the linked cost unit to sold, consumes aggregate on-hand/reserved quantity, and records immutable serialized COGS.
- Order COGS snapshots retain product/store/line references, unit cost, quantity, source-cost reference and paid timestamp.
- Service-role-only export writes negative `cost_of_goods_sold` financial facts using the store's business timezone and stable order/line references.
- Contract tests: `tests/build009-serialized-checkout-cogs-bridge.test.mjs`.
- CI workflow: `.github/workflows/build009-serialized-checkout-cogs.yml`.

## Critical transaction rules
- The original Build 001 idempotency key and payment event uniqueness rules remain authoritative.
- Payment success is accepted only through the existing trusted, signature-verified Stripe webhook adapter; this migration does not implement or bypass signature verification.
- A paid order without a consumed reservation, matching serialized unit, matching store/product, and valid cost record fails the database transaction.
- Reservation expiry/failure releases the cost reservation. A late payment after reservation expiry remains in the existing refund-review path; it does not silently resell unavailable inventory.
- Sale-time COGS snapshots are unique by order line and cannot be overwritten by later receipt-cost changes.
- No card PAN, CVV, PIN, or payment credentials are stored.

## Boundaries
- This change integrates the existing serialized checkout path; it does not itself publish serialized products to the website, configure Stripe, enable production webhooks, or deploy the website.
- The bridge expects checkout-ready receiving to be used for new serialized inventory. Existing legacy serial records without a matching Build 009.38 cost record are not eligible for paid checkout through this bridge.
- Serialized returns, warranty registration/claims, inspection/condition grading, and resale disposition are deliberately separate lifecycle work and are not claimed as implemented here.
- The current migration stores serial/IMEI digests in the cost ledger; the legacy Build 001 unit table still retains the raw serial/IMEI fields. Existing access controls on that table remain in force and require a separate privacy review before customer-facing display or broader staff access.

## Validation required before merge
- `npm run lint`
- `npm run test:build009:serialized-checkout-cogs`
- `npm run test:build009:inventory-cogs`
- `npm run test:build009:native-financial`
- `supabase db reset --local`
- `supabase test db --local`
- `supabase db lint --local`

Integration tests must exercise checkout-ready receipt creation, duplicate serial rejection, two-person approval, checkout reservation, parallel reservation attempts, payment failure release, expiry, duplicate Stripe event delivery, amount/currency mismatch, successful payment, exact inventory decrement, COGS snapshot idempotency, and financial export idempotency across store timezones.

## Rollout
Review and merge only after CI and a disposable Supabase database replay succeed. No production migration, live checkout enablement, or website deployment is claimed.
