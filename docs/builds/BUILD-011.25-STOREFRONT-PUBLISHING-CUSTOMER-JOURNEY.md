# Build 011.25 — Storefront Publishing & Customer Journey

## Objective
Improve the public storefront journey without presenting incomplete commerce capabilities as operational. Changes are additive and preserve existing authentication, inventory, payment, and employee workflows.

## Changes
1. Customer account page: clarify that customer access is separate from employee access; retain existing sign-in, registration, and sign-out API flows; label shopping bag accurately.
2. Shopping bag route: add `/cart` so existing links no longer produce a missing-route response. The page clearly states that online cart/checkout is not open and does not collect payment or create an order.
3. Product catalog route: retain the honest catalog-readiness message and category exploration; do not invent stock, product prices, specifications, delivery promises, or promotions.
4. Mobile navigation: expose the main navigation links on small screens instead of hiding all primary navigation.
5. Metadata: cart is non-indexable; customer pages retain canonical and privacy-aware metadata as appropriate.

## Acceptance and verification
- [x] Customer account page no longer describes employee and customer access as interchangeable.
- [x] Shopping bag route exists with explicit no-checkout/no-payment disclosure.
- [x] Product page explains catalog availability without fabricated listings.
- [x] Mobile homepage navigation is visible at widths up to 640px.
- [ ] Vercel preview build completes successfully for the final commit.
- [ ] Verify homepage, products, cart, account, employee sign-in, and customer confirmation routes in preview.
- [ ] Verify customer registration/sign-in only after preview secrets and rate-limiter service are configured.
- [ ] Verify keyboard navigation, focus visibility, mobile layout, and no runtime errors.
- [ ] Obtain explicit release approval before production promotion.

## Routes in this milestone
- `/` — marketing homepage
- `/products` — catalog category/readiness page
- `/cart` — shopping bag readiness page; checkout intentionally disabled
- `/account` — customer account
- `/employee-sign-in` — separate employee authentication
- `/auth/customer-callback` — customer email confirmation callback

## Deferred / not represented as live
- Product inventory listings and live prices
- Cart persistence and stock reservation
- Tax/shipping calculations
- Checkout, Stripe payment capture, refunds, and order confirmation
- Financing application and lender decision workflow
- Customer account activation administration
- Newsletter subscriptions and marketing consent collection

## Release decision
**PREVIEW ONLY — NOT APPROVED FOR PRODUCTION.** Vercel preview verification and end-to-end acceptance tests are required. This build does not merge branches, change production environment variables, mutate production data, or deploy to the production domain.
