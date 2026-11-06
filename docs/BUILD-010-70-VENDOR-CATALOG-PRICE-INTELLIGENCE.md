# Build 010.70 — Purchasing & Vendor Management: Catalog and Price Intelligence

## Existing source-of-truth preserved
Build 010.70 extends the existing Build 010.45 procurement, Build 010.23 purchasing, Build 010.29 accounts-payable/vendor management and Build 010.44 inventory-control foundations. No duplicate vendor master, purchase order, inventory item or AP ledger is created.

## Added
- Vendor-specific catalog items with vendor SKU, vendor product name, brand, manufacturer part number, optional product URL and mapping to canonical MME inventory item.
- Supplier price offers with unit cost, currency, minimum order quantity, optional available quantity and lead time, validity dates, source reference and verification timestamp.
- Itemized supplier quote lines with product/description, quantity, unit price, currency, availability and lead-time evidence.
- Procurement API reads/writes and dashboard controls for catalog mapping, offers and quote line capture.
- Vendor price comparison display sorted by unit cost.

## Controls and limitations
- Prices are supplier-entered evidence, not automatically fetched or independently verified. Verification timestamp records staff attestation only.
- Price comparison currently sorts by unit cost and displays MOQ/availability/lead time; it does not calculate landed cost, tax, shipping, rebates, payment terms, FX normalization, or best-value recommendations.
- Offer expiry/status and currency normalization require server-side filtering before purchase decision; do not treat this list as a binding live quote.
- No vendor catalog ingestion, supplier API/EDI integration, automatic price refresh, PO auto-generation, vendor payment execution, or external purchase commitment is included.
- Existing procurement/PO/AP controls remain authoritative; review their separate tests and release gates.

## Validation
Run `npm run test:build010:vendor-catalog`, `npm run test:build010:procurement`, `npm run test:build010:purchasing`, `npm run test:build010:ap-vendor`, inventory suites, `npm run lint` and `npm run build`. Not executed in this change. Migration not applied; not merged or deployed.
