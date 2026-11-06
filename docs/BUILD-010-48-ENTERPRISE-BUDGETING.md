# Build 010.48 — Enterprise Budgeting, Departmental Controls & Expense Management

## Delivered
- Fiscal-year budget plans with controlled statuses and independent approval.
- Company, department, store, cost-center and capital-project dimensions.
- Dated budget allocations and CAPEX classification.
- Employee expense submissions and review queue.
- Expense approval/rejection RPC prevents submitter self-approval.
- Budget approval RPC prevents creator self-approval.
- Spending policy configuration foundation.
- Budget actuals import ledger with source-reference uniqueness.
- Approval and audit ledgers.
- Finance/management authenticated API, dashboard and acceptance contracts.
- RLS enabled and direct client access revoked; service-role backend only.

## Release boundaries / follow-up
- No automated GL/AP/POS/payroll/purchasing actual ingestion or budget-vs-actual calculations yet.
- No private receipt upload integration, malware scanning, receipt OCR or retention policy. Receipt path is metadata only.
- No complete multi-step approval routing, delegation, threshold-based policy enforcement, PO authorization or payment execution.
- Spending policy table is configuration foundation; the API does not yet enforce its thresholds.
- Department/store data is not yet scoped to individual manager assignments. The current API permits the listed management/finance roles to read all returned records. Production deployment requires dimension-level authorization and least-privilege role scoping.
- No budget line immutability after approval/locking enforcement at database trigger level; prevent edits to approved plans in next hardening pass.
- Budget-versus-actual report and variance alerts remain future work.
- Do not store receipt files in a public bucket or expose service-role keys client-side.
- Finance approval authority, segregation of duties and role claim mapping require production validation.

## Validation
Run `npm run test:build010:budgeting`, `npm run lint`, and `npm run build`. Apply migration after Builds 010.43–010.47 in staging. Test self-approval rejection, independent budget approval, invalid dates/amounts, policy threshold enforcement gap, private receipt access, manager dimension isolation, RLS, audit and actual-source deduplication. Not merged, migrated or production deployed.
