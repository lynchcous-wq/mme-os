# Build 010.54 — Enterprise Expense Management & Purchasing Controls

## Added
- Vendor directory and payment terms metadata.
- Employee expense report and expense item records with receipt reference/path fields.
- Submitter-owned expense submission and independent reviewer decision RPC.
- Reimbursement status register (no payment execution).
- Purchase requisitions and purchase order headers/lines.
- Generated purchase order line totals and tax-inclusive totals.
- Corporate card transaction evidence with provider reference uniqueness.
- Recurring expense schedule records.
- Finance API read and create actions plus dashboard panels.
- RLS/service-role-only table grants and acceptance contracts.

## Explicit release boundaries
- No receipt upload/storage authorization workflow is implemented; receipt path is metadata only.
- Expense item creation does not yet enforce report-owner access at the API boundary. Because service-role database access bypasses RLS, this is a production-blocking authorization gap. Add explicit report owner/finance permission checks before enabling employee use.
- Expense approval is one reviewer step, not configurable thresholds or multi-level routing.
- Requisition approval/conversion workflow and purchase order approval/send/receiving actions are not implemented; records can be created but this is not a complete procurement lifecycle.
- No vendor payment, ACH, corporate card issuer feed, reimbursement payment or recurring payment execution.
- No vendor onboarding/KYB, tax form collection, sanctions screening or bank detail storage.
- No automated GL posting, budget encumbrance, three-way PO/invoice/receipt match, or spending limit enforcement.
- Employee self-service and department/store row-level scope need implementation and testing before production.
- Validate finance-role authorization and all referenced schema dependencies in staging.

## Validation
Run `npm run test:build010:expense-procurement`, `npm run test:build010:financial-planning`, `npm run lint`, and `npm run build`. Apply migration only after reporting entity schema is installed. Not merged, migrated or production deployed.
