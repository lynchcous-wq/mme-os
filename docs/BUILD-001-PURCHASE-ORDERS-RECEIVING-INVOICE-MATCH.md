# Build 001 — Purchase Orders, Receiving & Invoice Matching

Status: proposed additive migration; not applied.

A formal purchase order is created only from a CEO-approved purchase proposal and an active supplier. Product descriptions, quantities, supplier SKU and cost are snapshotted into PO lines. The trusted service must enforce employee roles and CEO approval; actor UUIDs are audit attribution, not authorization.

The order lifecycle records draft, submitted, approved/rejected, issued, acknowledged, partially received, received and cancelled states. Each transition writes an event. This migration does not send supplier emails, EDI/API orders, or payments.

Receiving accepts PO line IDs and quantities, rejects duplicate/unknown lines and quantities above the remaining balance, and calls the existing inventory receipt transaction. Partial deliveries update received quantity; final delivery marks the PO received.

Invoices are stored against the PO with line quantities and unit costs. Matching compares invoiced quantities to received quantities and unit costs/totals to PO values with explicit tolerances. Variances require human review. Matching does not authorize payment.

Shipment milestones and supplier acknowledgments are manually recorded; carrier polling/webhooks and external transmission are not implemented. Invoice documents must use private storage with validated object paths and expiring signed access. Accounts-payable approval and payment execution remain separate builds.

Apply this migration after the proposal, supplier and receiving migrations in a disposable database. Test approval gating, state transitions, duplicate PO numbers, partial and over-receiving, unknown line IDs, invoice variances and rollback. Do not merge or deploy based only on static test definitions.