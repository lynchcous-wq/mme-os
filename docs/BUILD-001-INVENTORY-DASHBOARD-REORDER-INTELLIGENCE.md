# Build 001 — inventory dashboard and reorder intelligence

**Status:** Proposed additive migration; not applied.

## Command view
Location-filtered inventory rows show SKU/title/category/condition, aggregate on-hand/reserved/available, average unit cost and aggregate inventory value, plus separate serialized counts for in-stock/reserved/sold/repair-or-quarantine units. Serialized unit value is intentionally excluded because a reliable per-unit landed-cost source is not yet wired into that ledger.

## Reorder intelligence
Each product/location can have a minimum available quantity, target quantity, lead-time days, preferred supplier, and enabled flag. When available aggregate quantity reaches or falls below the minimum, suggested reorder quantity is target minus available. Serialized units are visible separately and are not included in aggregate reorder arithmetic.

## CEO/manager controls
Rules are changed through a service-role-only RPC. The trusted server must verify the caller's MME role, require CEO approval for policy/threshold changes, and verify the approver is authorized. The supplied identity UUIDs are audit attribution, not authorization. Never expose service-role credentials to browsers.

## Dashboard safeguards
- Supports location, SKU/title search, low-stock-only filter, and bounded pagination.
- Inactive products/locations are excluded.
- Aggregate inventory value = on-hand quantity × weighted average unit cost; it is not retail value or profit.
- Held/damaged aggregate units are excluded because the inspection workflow removes them from sellable on-hand.
- No automated purchase orders are created. Recommendations are decision support only until the CEO approves a procurement workflow.

## Required verification
Apply migrations in order on a disposable Supabase database. Test multi-location totals, serialized vs aggregate separation, threshold boundary, zero stock, disabled rules, pagination, and CEO approval in the trusted server adapter. Confirm view access through service-role backend only.
