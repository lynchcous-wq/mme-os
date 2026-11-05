# Build 008 / Build 001 catalog integration

Build 001 owns the authoritative product catalog. Build 008 consumes the catalog and inventory availability as a downstream integration. This change is additive and does not enable production checkout, deploy, or merge.

## Public response boundary

- Return only published, active products.
- Never expose device serial numbers, IMEIs, supplier costs, employee identities, inspection evidence, internal location codes, or storage keys.
- Serialized stock availability is based on individually eligible in-stock units; customer responses expose aggregate availability only.
- Quantity-tracked availability subtracts reservations once and never falls below zero.
- Validation does not reserve inventory or create payment intents.

## Verification

The route suites run with `npm run test:build008:catalog-routes`. They include source-contract checks, migration dependency checks, and handler-level tests that import the TypeScript route handlers and mock Supabase REST responses. The handler tests verify published-product filtering, reservation-aware quantity availability, media-field allowlisting, aggregate-only serialized availability, and cart rejection when stock is insufficient. GitHub Actions installs dependencies before running the suites.
