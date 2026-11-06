# Build 010.71 — Intelligent Purchasing & Automated Procurement

## Implemented
- Supplier landed-cost scenario ledger: quantity, unit cost, shipping, duties, tax, fees, discount, currency, notes, actor and timestamp.
- Supplier price observation history with source reference, observation timestamp and recording user.
- Authenticated procurement API read/write actions for both records.
- Dashboard landed unit cost calculator and saved scenario history.
- Supplier price observation capture and comparison against catalog offer price.
- Descriptive vendor review averages from recorded delivery, quality, price and service metrics.
- RLS enabled; direct anon/authenticated table access revoked; service role used through authenticated server API.

## Decision-support boundaries
- Calculations assume all entered amounts are in the same currency. No FX conversion, tax recoverability, tax jurisdiction rules, freight allocation, customs classification, rebates or accounting capitalization policy is applied.
- Price observations are manually entered and not provider-verified. A displayed change compares the latest observation with the current catalog offer; it is not necessarily a chronological price change from the prior observation.
- Vendor ranking is a simple descriptive average across available review metrics; it is not normalized, weighted, statistically validated, or a risk/compliance decision.
- No autonomous vendor selection, order submission, PO creation, vendor payment, or external purchasing commitment.
- Do not enable production purchasing decisions until finance/procurement approval controls, currency rules, supplier quote validity, source evidence, and full test suites are verified.

## Validation
Run `npm run test:build010:intelligent-purchasing`, vendor-catalog, procurement, purchasing, AP-vendor, inventory suites, `npm run lint`, and `npm run build`. Tests not executed in this change. Migration not applied; not merged or deployed.
