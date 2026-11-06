# Build 001 — Warehouse Bin & Putaway Operations

**Status:** Proposed additive migration; not applied.

Adds location-scoped warehouse bins with zone, aisle, rack, shelf, type and optional unit capacity. Bin balances track aggregate product allocation while `mme_inventory_balances` remains the authoritative location-level on-hand ledger.

Putaway can allocate only stock already present in the location balance and not already allocated to another bin. Within-location bin moves lock rows in deterministic order, enforce source quantity and destination capacity, and write an immutable movement record.

Serialized devices remain managed by the existing per-device location and movement workflows. This migration does not replace inter-store transfers, purchase receiving, cycle counts or the aggregate stock ledger.

All tables and RPCs are service-role only. The backend must verify employee identity, role, location scope and authorization; identity UUID parameters are audit attribution, not authentication. Pick operations should be integrated with the POS reservation/fulfillment workflow before being exposed to staff.

Verification: run disposable-database integration tests for over-allocation, insufficient source bin stock, cross-location bin moves, inactive bins, capacity overflow, concurrent transfers and bin totals against location on-hand.