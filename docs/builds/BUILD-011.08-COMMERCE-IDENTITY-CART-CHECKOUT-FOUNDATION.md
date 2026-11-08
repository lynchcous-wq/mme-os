# Build 011.08 — Commerce Identity, Cart & Checkout Foundation

Status: **implementation plan and repository audit committed; application implementation and runtime validation pending**.
Branch: `implementation/build-011-08-commerce-identity-cart-checkout`.
Base: `implementation/build-011-purchasing-receiving-integration`.
Date: 2026-11-08.

## Objective

Prepare the MME storefront for secure customer and employee access, persistent shopping carts, and Stripe-backed checkout without replacing prior builds or creating parallel identity, inventory, order, or payment authorities.

This build is the next commerce-priority workstream. It is additive and must preserve all existing routes, migrations, build documentation, and deployed production behavior until the new path passes its acceptance tests.

## Repository audit — confirmed observations

The following observations were made against the Build 011 purchasing/receiving branch:

- `package.json` includes Next.js, React, React DOM, TypeScript and type packages only. No Stripe SDK or authentication SDK is declared in this branch's package manifest.
- `app/layout.tsx` is a minimal root layout with global CSS and metadata.
- `app/account` and `app/products` exist as routes, but the account and product pages inspected in the preceding deployment audit are placeholders.
- The homepage links to account, cart and employee sign-in destinations, but the preceding deployed route inventory did not include working `/cart` or `/employee-sign-in` routes.
- No Stripe checkout integration has been verified. A successful Vercel deployment is not evidence of configured Stripe credentials, webhook delivery, successful payment, or order creation.
- Earlier MME identity work includes identity/role schema artifacts. This build must inspect and reuse the canonical identity tables and policies rather than creating a second user/person/role system.

These are repository/deployment observations only. They do not establish the current state of the live Supabase project, Vercel environment variables, Stripe account, or payment processor configuration.

## Non-negotiable architecture rules

1. **One person identity:** customer and employee capabilities may belong to the same person and login identifier. Do not create separate competing user identities.
2. **Role-based authorization:** customer, employee, manager, administrator and executive capabilities must be granted by server-verified roles and permissions, never by client-supplied role values.
3. **Employee lifecycle isolation:** disabling or terminating employee access must not erase or disable that person's separate customer access. Employee sessions and privileged permissions must be revoked independently.
4. **Additive-only changes:** no destructive migration, route removal, table replacement, or duplicate build. Preserve existing contracts and create compatibility adapters where required.
5. **Server authority:** prices, discounts, tax, inventory availability, shipping, order totals, payment status and permissions must be recalculated/validated on the server.
6. **Payment integrity:** never store card numbers, CVV or raw payment credentials. Use Stripe-hosted/embedded secure payment collection and server-created PaymentIntents or Checkout Sessions.
7. **Webhook authority:** order payment state changes only from verified, idempotently processed Stripe webhook events or a trusted server-side reconciliation path. Never trust a browser redirect as proof of payment.
8. **No false live claims:** sandbox tests, local tests and production transactions must be distinguished. Do not claim live payments work until secrets, webhook signing, account configuration and a controlled end-to-end test are verified.

## Phase A — Identity and session audit

Before implementation, inspect:

- Existing Supabase migrations, including identity/person/role tables, auth-user mapping, RLS policies, grants and helper functions.
- Existing sign-in, callback, middleware, session and API routes.
- Any existing identity audit/event tables and account-freeze controls.
- Vercel project environment-variable *names and presence only*; never print or expose secret values.
- Current Supabase Auth provider settings and redirect URLs through authorized project configuration.

Required behavior:

- Customer sign-up/sign-in and account recovery.
- Employee sign-in using the same canonical person identity.
- Server-side session validation and secure cookie/session handling.
- Role/permission checks on every protected server action and route.
- CEO/authorized administrator account freeze and access revocation with immutable audit events.
- Customer profile remains usable if employee access is terminated.
- Rate limits, abuse controls, generic authentication errors, secure password reset and session revocation.

Do not invent or silently assume an authentication provider. Reuse the existing configured Supabase Auth authority if confirmed; otherwise document the missing configuration and propose a decision before introducing another provider.

## Phase B — Cart and catalog integration

Required behavior:

- Add `/cart` route and accessible cart controls.
- Support anonymous cart state with a safe merge into the authenticated person's cart after sign-in.
- Persist authenticated carts server-side with ownership enforced by RLS.
- Preserve product identity, SKU/variant, quantity and price snapshot references.
- Revalidate current price, sellable status, inventory, serial/IMEI constraints and quantity limits before checkout.
- Prevent overselling with transactional inventory reservation/commit logic connected to the canonical inventory ledger.
- Support shipping and local pickup as explicit fulfillment choices.
- Apply approved discounts, subscription benefits, financing eligibility and tax through authoritative server-side services; do not trust browser totals.
- Show unavailable, changed-price and insufficient-quantity conditions before payment.

Do not build a second product catalog or inventory balance table. Connect to the canonical catalog and stock ledger after their current authority is identified.

## Phase C — Stripe checkout and order lifecycle

Required behavior:

- Confirm the existing Stripe account, mode, business identity and approved products/regions before enabling live mode.
- Keep Stripe secret key and webhook signing secret exclusively in server-side environment variables.
- Create a pending order and inventory reservation before redirecting to payment.
- Create Checkout Session/PaymentIntent on the server using the server-calculated amount and currency.
- Store Stripe customer/session/payment identifiers as references only.
- Verify webhook signatures against the raw request body.
- Make webhook processing idempotent using Stripe event IDs and a durable event ledger.
- Handle successful, failed, canceled, expired, refunded, disputed and asynchronous payment states.
- Finalize the order and inventory movement exactly once after confirmed payment; release reservations on expiration/failure under a documented policy.
- Generate customer receipt/order confirmation and employee-visible order record.
- Never expose secret keys, raw card data or privileged payment metadata to the client.

Live payment enablement is blocked until webhook delivery and reconciliation are verified in the production environment. Begin in Stripe test mode.

## Phase D — Tests and release gates

Automated tests must cover:

- Customer registration, sign-in, sign-out, recovery and session expiry.
- Employee sign-in, role boundaries, manager/admin access and terminated-employee revocation.
- One person with both customer and employee roles.
- Cross-account access denial for profiles, carts and orders.
- Anonymous-to-authenticated cart merge and duplicate-line handling.
- Price tampering, discount tampering, tax/total tampering and invalid SKU/quantity rejection.
- Inventory race conditions and reservation expiration.
- Stripe test-mode success, decline, cancel, duplicate webhook, invalid signature, refund and delayed webhook.
- Order/payment/inventory consistency under retries and partial failures.
- Accessibility, responsive layouts, CSRF/origin controls, rate limits and security headers.

Release sequence:
1. Local typecheck/build and automated tests.
2. Preview deployment using test credentials only.
3. Preview end-to-end tests with Stripe test mode and webhook forwarding.
4. Production environment configuration review without exposing secret values.
5. Controlled production smoke test only after explicit readiness approval.
6. Promote/deploy only when checks pass; preserve the current production deployment as rollback target.

## Acceptance criteria

Build 011.08 is **not complete** until all of the following are evidenced:

- Working customer and employee sign-in using one canonical person identity.
- Customer and employee access can be granted/revoked independently.
- Server-enforced roles and RLS prevent cross-account and privilege escalation.
- A cart persists and correctly merges across sign-in.
- Checkout totals are calculated server-side from canonical catalog, inventory, tax and fulfillment authorities.
- Stripe test-mode payment success/failure/cancel/refund flows pass.
- Verified, idempotent webhooks create/finalize orders and inventory movements exactly once.
- Production live payment readiness is separately documented and verified.
- CI build, typecheck, automated tests and preview smoke tests pass.
- No previous build, route, migration, or source-of-truth authority is removed or duplicated.

## Current disposition

This commit establishes the workstream and its guardrails only. It does **not** implement authentication, cart persistence, Stripe checkout, payment webhooks, or production live payments. The next implementation action is a targeted audit of the existing identity migrations, auth routes and Supabase policies, followed by the smallest compatible code change.
