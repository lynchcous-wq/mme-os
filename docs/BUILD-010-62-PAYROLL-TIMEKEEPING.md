# Build 010.62 — Payroll & Workforce Timekeeping

## Implemented
- Attendance clock event ledger with clock-in, clock-out and break transition validation.
- Time entry records with submission and manager review states.
- Initial regular/overtime minute split (8-hour daily threshold).
- Payroll period and run records.
- Payroll line-item ledger for earnings, deductions, employer contributions and memo items.
- Independent approval check preventing run creator from approving own run.
- Paystub metadata registry with checksum.
- ACH/check/manual payment batch metadata.
- Positive Pay export metadata.
- Authenticated API, dashboard, RLS/service-role-only grants and acceptance contracts.

## Production blockers
- Time rounding, overtime, breaks, minimum wage, state/federal labor rules, holidays, multiple rates, weekly aggregation and jurisdictional rules are not implemented. The 8-hour split is a placeholder, not a compliance determination.
- No payroll tax calculation, withholding, benefit deduction, garnishment, net-pay validation, paystub rendering, direct deposit, ACH file transmission, bank connection, Positive Pay file generation or bank submission.
- Payroll run totals are derived from manually entered line items; no calculation engine or approved source-of-truth integration exists.
- Payroll run review/approval and its audit event are multiple requests, not atomic; add transactional RPC, idempotency and immutable audit.
- Restrict employee records and paystub access to employee self-service scope; current API role allowlist is not a complete authorization model.
- Validate time-event chronology under concurrency and prevent duplicate/open shifts with transactional constraints.
- Payment batch metadata creation is not payment execution; reconcile batch amount to approved run net total before any provider integration.
- Confirm employee identity mapping, payroll vendor integration, retention, encryption, and HR/legal/payroll approval.

## Validation
Run `npm run test:build010:payroll-timekeeping`, existing identity/HR/payroll suites, `npm run lint` and `npm run build`. Tests not executed, migration not applied, not merged or production deployed.
