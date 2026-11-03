# MME OS

Greenfield storefront and operations platform foundation for Much More Electronics.

## Current milestone

Initial responsive storefront shell with a home page, navigation, sample product cards, and placeholder product/account routes. Product details and prices are illustrative only. There is no live catalog, account system, checkout, Stripe connection, or inventory integration yet.

## Stack

- Next.js App Router
- React
- TypeScript
- CSS

## Run locally

Requires Node.js 20.9+ and npm.

```bash
npm install
npm run dev
```

Open http://localhost:3000.

## Next milestones

1. Database-backed products, stock, and CEO pricing approval.
2. Customer identity and separate employee/CEO permissions.
3. Cart, shipping/pickup, tax, Stripe Checkout, verified webhooks, and reconciliation.
4. Internal system integrations, security, analytics, and production verification.

Do not use the sample catalog as real inventory or pricing. Do not enable live payments until order creation, webhook processing, idempotency, and reconciliation are implemented and tested.
