# Build 010.65 — Enterprise Procurement & Vendor Management

## Implemented
- Vendor directory/onboarding record.
- Purchase requisition and line-item tables.
- Requisition submission endpoint with line validation and estimated total.
- Assigned-approver decision RPC; row locks approval, requires assigned approver, transitions supported subject state and appends audit event.
- Vendor contract register with date constraints and lifecycle.
- Competitive vendor quotation register.
- Purchase order and PO line registers.
- Receiving match register.
- Return-to-vendor and return line registers.
- Vendor performance scorecards.
- Authenticated procurement API, dashboard, RLS and acceptance contracts.

## Production blockers
- Vendor creation currently sets inactive but does not create a vendor approval request; onboarding verification and duplicate/tax/bank validation remain.
- Requisition submission currently updates header, creates approval in separate requests and permits caller-supplied approver identity. Server-side approval routing must select authorized approvers from policy; no client may assign their own approver.
- Approval RPC does not enforce multi-level threshold rules, requester/approver separation, PO line requirements or approval policy by budget.
- Contract document upload, legal review, signature and renewal alerts are not implemented.
- Quote selection, scoring/award workflow, PO line CRUD, PO approval orchestration, PO dispatch and vendor acknowledgements are not implemented.
- Receiving three-way match against PO and AP invoice is register-only; inventory receipt linkage and discrepancy holds remain.
- Return shipment, inventory decrement, vendor credit memo and AP settlement are not connected.
- Budget encumbrance, spend limits, tax compliance, sanctioned supplier checks, bank detail verification and payment execution are not implemented.
- Restrict procurement role access by department, store, budget and assigned approval scope. Service-role API operations need strict server-side least privilege, idempotency and audit coverage.
- Validate procurement data retention, document access, supplier privacy and external legal/accounting policies before production.

## Validation
Run `npm run test:build010:procurement`, existing inventory/finance/identity suites, `npm run lint` and `npm run build`. Tests not executed, migration not applied, not merged or production deployed.
