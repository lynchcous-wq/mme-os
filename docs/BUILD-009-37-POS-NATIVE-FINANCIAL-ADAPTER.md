# Build 009.37 — Native MME POS Transaction Source Adapter

Status: implementation committed to a review branch. Fresh-database migration replay, automated CI, and transaction-level end-to-end validation remain pending.

## Objective
Connect authoritative MME POS orders and finalized transactions to Build 009.32 financial reporting, through Build 009.34/009.35 staging and import controls where appropriate. Native POS facts are written directly from the authoritative transaction tables using a leased, idempotent export ledger. Stripe balance transactions remain payment-movement evidence and must not be counted as a second sale.

## Delivered
- `supabase/migrations/20261105001170_build009_pos_native_financial_adapter.sql`
- Renumbered the pre-existing duplicate-version Build 009 tender-reconciliation migration from `20261105000930` to `20261105000931` so a fresh Supabase migration replay can proceed.
- `app/api/cron/pos-native-financial-export/route.ts`
- `app/api/pos/transactions/[transactionId]/register/route.ts`
- Updated `app/api/pos/financial-connectors/route.ts`
- Updated `app/internal/financial-connectors/page.tsx`
- Updated Stripe balance normalizer: charge/payment -> `payment_capture`; refund -> `payment_refund`.
- `tests/build009-pos-native-financial-adapter.test.mjs`
- `npm run test:build009:native-financial`
- `.github/workflows/build009-native-pos-financial.yml`
- Five-minute Vercel Cron schedule.

## Source-of-truth and transaction eligibility
- Build 001 `mme_orders` and `mme_order_lines` remain the order, item and pricing source of truth.
- Build 009 `mme_pos_transactions` remains the POS state and finalized timestamp source of truth.
- Build 009 tender attempts remain the payment status and captured amount source of truth.
- Build 009 refund requests remain the completed refund source of truth.
- A financial export is eligible only after POS transaction status is `finalized`, order/transaction currency and totals match, order lines reconcile to subtotal, all lines belong to exactly one store, and captured tender amounts sum exactly to the order total with no unresolved tender states.
- Store location is derived from the active inventory reservation at transaction creation and backfilled only where historical reservation lines show exactly one distinct store. Cross-store and missing-store records are blocked for review.
- Each store now has a validated IANA `business_timezone` setting, defaulting to `America/New_York` until a store administrator sets the correct local value.
- Register reference is optional for historical compatibility, but can be assigned only while the transaction is still `inventory_reserved`; later changes are rejected. The authenticated endpoint does not trust a browser-supplied employee identity.

## Financial fact mapping
- Each order line -> one `gross_sale` fact, preserving SKU, category, quantity, line amount, register and cashier.
- Fulfillment charge -> separate `gross_sale` fact with category `fulfillment`.
- Order-level discount -> one negative `discount` fact.
- Order tax -> one positive `sales_tax` fact.
- Each provider-confirmed captured tender -> `payment_capture` evidence fact.
- Each completed refund -> negative `refund` fact plus a separate negative `payment_refund` evidence fact.
- `payment_capture` and `payment_refund` are explicitly excluded from net-sales aggregation. Stripe maps to the same movement-only fact types, avoiding duplicate revenue.
- Chargebacks, positive chargeback reversals and processor fees continue to come from payment provider activity and are not invented from POS orders. Financial report rebuilds net chargeback and reversal facts together.
- COGS is not guessed from retail price or an equal-cost allocation; inventory/COGS source integration remains a separate adapter dependency.

## Idempotency, retry and closed periods
- One export ledger row per POS transaction; bounded worker leases and `FOR UPDATE SKIP LOCKED` prevent concurrent duplicate processing.
- Stable source references are generated for each line, discount, tax, fulfillment charge, tender capture and refund.
- Financial fact imports are immutable and source-reference idempotent. Exact replays return the existing fact; conflicting replays are rejected.
- A completed export is periodically rescanned so later completed refunds are picked up; already-exported facts remain idempotent.
- Closed periods reject new facts. Exact existing facts may be replayed without mutating the ledger. New refunds after close require the existing authorized close/reopen/adjustment workflow.
- Failed export attempts store safe error codes, not raw provider or payment data.

## Security
- Export queue and event ledger have RLS enabled; direct anon/authenticated table access is revoked.
- RPC functions are service-role-only and independently validate the employee worker identity and store-scoped `pos.finance.report.import` permission.
- Cron endpoint requires `CRON_SECRET`; worker identity uses `MME_FINANCIAL_WORKER_PERSON_ID`; Supabase service credentials remain server-only.
- No PAN, CVV, PIN, magnetic-stripe data or raw payment method data is stored.
- Per-store timezone is validated against PostgreSQL `pg_timezone_names`.

## Validation and rollout
Run:
- `npm run test:build009:native-financial`
- `npm run test:build009:financial-provider-sync`
- `npm run lint`
- `supabase db reset --local`
- `supabase test db --local`
- `supabase db lint --local`

End-to-end validation must create an order with inventory reservation, create/finalize a POS transaction using fully captured test tenders, run the native export, confirm sales/discount/tax/payment facts, repeat the export without duplicates, then complete a test refund and verify it is added once. Also test multi-store rejection, timezone boundary dates, missing register attribution, expired worker leases, closed-period rejection and refund-after-close handling.

No production migration, live POS transaction export, Stripe production sync, website deployment, or successful CI run is claimed.
