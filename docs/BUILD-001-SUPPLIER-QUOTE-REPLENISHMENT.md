# Build 001 — Supplier Quote Intelligence & Automated Replenishment Drafts

**Status:** Proposed additive migration; not applied.

## Supplier comparison
The quote comparison view exposes current valid USD quotes from active suppliers, ranked by unit price and lead-time tradeoff. Historical quotes remain in the append-only supplier quote ledger; expired quotes do not qualify as current recommendations.

## Forecast-driven draft generation
The trusted purchasing service can create an editable draft for one active store location. It reads forecast-enabled aggregate products requiring replenishment, selects the lowest valid supplier unit quote (then lead time), and honors the supplier minimum order quantity. Each proposal line retains the supplier, source quote ID and quote snapshot.

If no valid supplier quote exists, the draft uses the current forecast/average cost estimate and explicitly flags that a manual supplier quote is required. It never invents a supplier or quote.

## Approval boundary
The function creates a **draft only**. It does not submit the proposal, approve spend, create/issue a purchase order, contact suppliers, or transmit payment. CEO/authorized purchasing approval remains a separate workflow. The PO creation screen should surface the recommended supplier and require an explicit supplier selection before order creation.

## Operational requirements
The trusted server authenticates the employee, verifies location and purchasing permissions, validates proposal reference uniqueness, and records audit context. No service-role key may be exposed to a browser. Before merge, run integration tests for MOQ rounding, quote expiry, inactive suppliers, missing quotes, no forecast-enabled products, proposal totals, and duplicate proposal references.