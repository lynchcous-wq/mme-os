# Build 010.40 — Enterprise Inventory Intelligence & Asset Management

## Delivered
- Product catalog with SKU, condition, unit cost, retail price and reorder point.
- Store, stockroom, warehouse, repair and transit location registry.
- Per-product/per-location stock balance ledger.
- Serialized asset registry with unique serial and IMEI indexes.
- Receipt, stock adjustment and inter-location transfer workflows.
- Database-locked stock movement and atomic two-sided transfer functions.
- Physical count records with generated variance.
- Audit ledger, restricted API, dashboard and acceptance contract tests.

## Controls and boundaries
- RLS enabled on all nine inventory tables; direct public/anonymous/authenticated table access revoked. Service-role access is intended only behind authenticated server routes.
- Stock movement function locks product, location and balance rows and prevents negative balances. Transfer function changes both location balances and writes paired movements within one database transaction.
- Product creation does not create stock. A receipt is required to add quantity.
- Serial/IMEI uniqueness is enforced; asset registration does not currently reconcile serialized asset counts with aggregate stock quantities.
- Receipt header creation and stock movement are separate API operations; if header persistence fails after movement, manual review is required. Production receiving should be moved into a single transactional RPC.
- Physical count creates a variance record only; it does not automatically adjust stock.
- No live POS sale completion, vendor purchase-order feed, shipping, storefront availability, automatic reorder, or inventory accounting valuation posting is connected yet.
- Validate existing inventory and opening balances before operational adoption.

## Validation
Run `npm run test:build010:inventory`, `npm run lint`, and `npm run build`. Apply migration in staging after Build 010.39; test RLS/service-role access, concurrent movement, insufficient stock rejection, transfer atomicity, duplicate IMEI/serial, and receipt failure recovery. Not merged, migrated or deployed.
