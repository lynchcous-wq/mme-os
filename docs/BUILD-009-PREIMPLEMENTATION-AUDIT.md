# Build 009 — Pre-implementation Repository Audit

**Branch:** `implementation/build-009-enterprise-pos`
**Base commit:** `80015b6f3a5df797fb7cb28b3c750dcb59df4fe1`
**Audit type:** Source-tree inspection only
**Status:** Initial audit recorded; no POS runtime implementation or provider integration claimed
**Specification:** `docs/BUILD-009-ENTERPRISE-POS.md`

## 1. Scope and preservation boundary

Build 009 is the Enterprise Point of Sale and Transaction Processing Engine. This audit starts the build on an isolated implementation branch. It does not merge into the current Build 008 work branch, change the production database, configure Stripe, enable hardware, or perform live transactions.

Preserve the existing MME storefront and Build 001/008 catalog and inventory contracts. POS must consume source-module APIs/RPCs and must not create a competing product, stock, payment, accounting, or commission ledger.

## 2. Observed repository facts

The inspected branch contains:

- A Next.js storefront homepage at `app/page.tsx`.
- Catalog API routes at `app/api/catalog/route.ts`, `app/api/catalog/[id]/route.ts`, and `app/api/catalog/[id]/units/route.ts`.
- A cart validation route at `app/api/cart/validate/route.ts`. Its response explicitly says validation only: it does not reserve inventory or create a payment.
- Build 001 catalog, order, reservation, serialized-unit, inventory movement, channel-claim and related migrations.
- Build 008 catalog/inventory documentation and contract tests.
- Build 004 identity schema/functions and tests on the base commit, with latest SQL migration validation still running at audit time.

The inspected application API route list contains no POS transaction, register-session, payment-intent, cash-drawer, receipt, refund, tax, or end-of-day routes. The inspected migration filenames contain order/reservation and inventory/channel-claim work, but no dedicated Build 009 POS/payment/register/tax/receipt migration set. The inspected SQL test filenames contain no Build 009 POS/payment tests.

The repository's inspected `package.json` contains Next.js, React and TypeScript. It does not establish a payment SDK, tax provider, terminal SDK, printer/drawer driver, accounting integration or production POS hardware connector.

These are observations about the inspected branch/tree, not claims about external accounts or services that may exist outside this repository.

## 3. Critical prerequisites and blockers

| Area | Current evidence | Build 009 treatment |
|---|---|---|
| Employee identity and authorization | Build 004 person-keyed foundation exists; SQL validation on base commit was not complete at audit time | Do not expose POS actions until server-side actor, employment, location and register authorization contracts are verified |
| Product/catalog | Build 001 catalog routes and schema exist | Read published catalog values; never accept browser-supplied price as authority |
| Inventory | Build 001/008 reservation and serialized-unit contracts exist | Use reviewed reservation/commit/release RPCs; no direct balance mutation |
| Orders | Order and reservation migrations exist | Crosswalk exact transaction/order states before defining POS sale finalization |
| Payments | No Build 009 payment integration established in inspected tree | Provider/account/webhook/Payments Center contract must be verified before payment code |
| Stripe | User previously stated an existing Stripe account, but no credentials, enabled products, terminal compatibility or webhook ownership verified here | Never assume a configured account or expose credentials; test mode first |
| Verifone M425 | Target hardware is named in Build 009 specification; no compatibility evidence in inspected tree | Do not claim support or enable it without acquirer/processor certification and exact firmware/SDK verification |
| Tax | No provider or tax calculation service established in inspected tree | Provider and jurisdiction policy decision required; no hardcoded rates |
| Cash drawer/printer | No device integration established in inspected tree | Hardware qualification and failure workflows required |
| Returns/refunds | Build 017 service status and interface are not established by this audit | Keep refund and inventory disposition separate; verify contract before integration |
| Accounting/commissions | No verified source-module APIs in inspected tree | POS emits stable transaction references only after authoritative contracts are identified |
| Build 006 tasks/notifications | Specification exists; runtime delivery contract not verified in this audit | Define durable event contract; do not assume alert delivery |

## 4. Safe implementation sequence

1. Complete dependency and API contract crosswalk for Build 001/008 inventory reservations, order lifecycle, payment event processing and serialized-unit ownership.
2. Verify Build 004 server-side person authorization, register/location scopes, privileged action audit and CI SQL test status.
3. Define POS transaction state machine and ownership boundaries in a reviewed architecture decision record. Distinguish cart, inventory reservation, payment pending/authorized/captured, sale finalized, refund pending/completed, and reconciliation-required states.
4. Build an authenticated, non-production POS shell and register-session interface only after authorization contracts are available. Keep all write actions disabled until server-side enforcement is implemented.
5. Add transactional orchestration with idempotency, durable failure states, inventory reservation/commit/release and audit tests.
6. Integrate payment provider in test mode only after Payments Center/provider configuration and webhook verification are inspected.
7. Qualify cash drawer, printer and Verifone M425 separately; unsupported hardware remains disabled.
8. Add tax, receipt, returns/refunds, accounting, commission, reporting and Build 006 events only against verified source contracts.
9. Require security, accessibility, recovery, provider sandbox, reconciliation and authorized operational sign-off before any production/live transaction.

## 5. Non-negotiable controls

- Never store or log raw PAN, CVV, PIN, track data or sensitive authentication data.
- Never trust browser-supplied prices, discount approvals, tax totals, employee permissions, terminal success messages or payment redirects.
- Verify payment provider webhooks using the raw request body and provider signature; deduplicate/replay-protect events.
- Bind each payment operation and inventory action to a durable transaction reference and idempotency key.
- Never blindly retry a payment whose outcome is unknown; reconcile provider state first.
- Inventory reservation is not a completed sale. Payment request is not capture. Refund request is not refund completion.
- Serialized units remain individually controlled and must not also be decremented from aggregate stock.
- Drawer/printer failure must not reverse an otherwise confirmed sale or payment.
- Keep test and live credentials/data separate. No live payment testing without explicit authorization and a reviewed plan.
- All privileged actions and overrides require server-side authorization, reason, actor attribution and immutable audit evidence.

## 6. Exit criteria for this audit phase

This audit phase is complete when the specification and repository findings are committed on the isolated Build 009 branch. It is not a production-readiness sign-off. The next implementation gate is a detailed transaction/order/payment/inventory state and API crosswalk; no checkout/payment UI should imply a successful sale before that gate is reviewed.

## 7. Known limitations

This audit inspected repository files and branch trees only. It did not access Stripe, a tax provider, terminal fleet, cash drawer, receipt printer, production Supabase, employee accounts, accounting, payroll, or live store operations. It did not execute migrations or POS tests. Absence from the inspected repository is not proof that an external service or device does not exist.
