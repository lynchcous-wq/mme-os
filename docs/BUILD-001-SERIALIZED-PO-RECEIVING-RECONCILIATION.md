# Build 001 — Serialized Device Receiving & IMEI Reconciliation

**Status:** Additive migration committed; not applied.

Adds a one-to-one receiving ledger linking each serialized device to its purchase-order line, scanner session, scan record, receipt reference, receiver and independent approver. Serialized intake requires an unresolved serialized SKU scan tied to the PO, an exact product/location match, remaining PO quantity, unique serial/IMEI values and a per-device landed-cost breakdown. Receipt intake updates the PO line quantity and writes an auditable PO event.

Session completion now supports serialized-only or mixed aggregate/serialized receipts. Every serialized scan must have a PO-line receipt link; unresolved, rejected, unmatched and duplicate scans continue to block completion. Aggregate units still use the existing atomic inventory receiving function. PO status is recalculated after both types are processed.

The approval identity must differ from the receiver. UUID arguments are attribution only: the trusted application server must authenticate both identities and authorize the receiving approval before invoking service-role functions. Migration is not applied and requires disposable-database execution of pgTAP tests before merge.