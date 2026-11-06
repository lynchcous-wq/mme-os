# Build 010.37 — Enterprise Financial Management & Accounting

## Delivered
- Chart of accounts with account-type constraints.
- General-ledger journal header and line ledgers; API validates balanced debit/credit totals before posting.
- Accounts payable invoice records and approval state.
- Accounts receivable invoice records and payment receipt ledger with overpayment guard.
- Bank account references and reconciliation worksheets with computed balance differences.
- Sales-tax period and jurisdiction reporting records.
- Restricted finance API, dashboard and audit ledger.

## Financial controls and boundaries
- Ledger entries are not bank transfers. Payables approval does not issue a check or ACH.
- Receivable payment entries are evidence records only; no payment processor is called.
- Bank reconciliation is a worksheet, not a verified bank feed or bank statement import.
- Sales-tax records do not determine tax liability, file returns or remit tax.
- Finance API roles and canonical person/account mapping must be verified against production authorization policy before release.
- Journal posting is validated in the API; concurrent/multi-request atomic posting needs a database transaction/RPC before production accounting reliance.

## Validation
Run `npm run test:build010:finance`, `npm run lint`, and `npm run build`. Apply in staging after Build 010.36, verify service-role grants, RLS, account references, audit persistence and journal rollback behavior. Not merged or deployed.
