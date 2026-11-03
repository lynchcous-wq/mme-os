# Build 001 — storefront catalog foundation

**Status:** Feature-branch implementation; demonstration catalog only  
**Branch:** `feature/build-001-catalog-foundation`

## Delivered
- Replaces the product-page placeholder with a responsive catalog experience.
- Search across product name, description, and listed specifications.
- Filter by new, pre-owned/used, and refurbished condition.
- Filter by televisions, computers, phones/tablets, wearables, and accessories.
- Combine search and filters; show a clear empty state and clear-filters link.
- Centralizes typed sample data and labels in `app/catalog.ts`.
- Uses URL query parameters so filtering survives refresh and can be shared.
- Adds a browser-local demonstration bag with quantity editing and removal; no server order is created.

## Data safety boundary
All six records are demonstration fixtures. Their prices, condition and specifications are illustrative only—not verified inventory, offers, or purchasable products. A local-only demo bag is available, but it does not reserve stock, create an order, or accept payment.

## Not included
Database-backed catalog, live stock, SKU/serial/IMEI records, CEO price approval, media management, cart, tax, shipping/pickup, orders, authentication, Stripe, and production analytics.

## Next
Connect approved catalog records after Build 004's security boundary is validated; then add stock and condition-grade details, persistent cart/order lifecycle, and Stripe test-mode Checkout only after signed webhooks, idempotency, and reconciliation are implemented and tested.


## Repository validation dependency
This draft pull request targets the repository-safeguards branch so the CI workflow can validate this dependent catalog change. It must be reviewed/merged only after its base safeguards PR is accepted; it remains separate from `main` until then.


## Cart demonstration increment

The catalog's sample records now support a browser-local demonstration bag. Visitors can add sample listings, change quantities, remove lines, clear the bag, and see a reactive item count. Bag contents are stored in that browser's local storage only.

This is not a customer cart or order record. It does not reserve stock, synchronize between devices, calculate tax/shipping, or create payment intents. The homepage product tiles are also explicitly labeled as illustrative examples. Newsletter signup remains disabled until a consent-aware customer communications service is connected.

### Manual browser acceptance checklist
- Add two different sample products and verify the bag count increments.
- Add the same sample product twice and verify quantity increments.
- Refresh and verify local demo bag contents persist in that browser.
- Change quantity, remove a line, and clear the bag.
- Verify no checkout, order confirmation, or payment action is exposed.
- Verify demo-price disclaimers remain visible on catalog and homepage.
