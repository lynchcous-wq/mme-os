# Build 001 — supplier management and vendor intelligence

**Status:** Proposed additive migration; not applied.

## Supplier directory
Private supplier profiles store supplier code, legal/display names, status, HTTPS website, contact details, payment terms, default lead time and notes. Status supports active, on-hold and inactive.

## Vendor catalog and price history
Supplier-to-product mapping retains vendor SKU and latest quoted cost. Each quote is also appended to immutable price history with minimum order quantity, quoted lead time, quote reference, validity, source type, timestamp and employee attribution. Quote history is a reference for comparison; it is not automatically a binding offer.

## Delivery tracking and scorecard
Delivery records link a supplier and optional purchase proposal, expected/received dates, expected/received/damaged units, status and quality notes. Scorecards summarize completion, non-damaged rate, schedule variance and delayed/disputed counts. Metrics require interpretation when delivery samples are small; no unsupported supplier ranking is asserted.

## Security and approval
All tables and scorecard view are service-role only. The trusted server must authenticate the employee, enforce role permissions, require CEO approval for supplier activation/terms and purchase decisions, and validate uploaded supplier documents before recording them. Actor UUID parameters are audit attribution, not authorization. Store supplier documents in private storage with signed expiring access.

## Scope limits
This does not transmit purchase orders, make payments, establish supplier credit, automatically import vendor feeds, or turn a proposal approval into an order. Actual PO issuance and receiving reconciliation remain separate controlled steps. Supplier scorecard date windows and sample thresholds belong in the application query layer before using metrics for purchasing decisions.
