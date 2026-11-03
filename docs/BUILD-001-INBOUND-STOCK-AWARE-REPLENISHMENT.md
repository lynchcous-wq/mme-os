# Build 001 — Inbound Stock-Aware Replenishment

**Status:** Additive migration committed; not applied.

The existing forecast recommendation is now netted against quantities on issued, acknowledged and partially received purchase orders. Only unreceived units count as committed inbound supply. Draft, submitted, approved-but-not-issued, rejected and cancelled POs are excluded, so tentative purchasing does not suppress replenishment recommendations.

The replenishment draft generator now:
- Calculates net need = forecast suggested quantity minus unreceived committed PO quantity, floored at zero.
- Omits products whose committed inbound supply already covers the forecast requirement.
- Applies the selected valid supplier quote and MOQ to the remaining need.
- Snapshots forecast quantity, inbound quantity, net need, open PO count and next expected delivery date on each proposal line.
- Continues to create an editable draft only; it never submits, approves or issues a PO.

The CEO retains final purchasing authority. Supplier MOQ may cause a proposal quantity to exceed net need and must remain visible for review. Forecast accuracy and real supplier delivery dates still depend on source data quality.