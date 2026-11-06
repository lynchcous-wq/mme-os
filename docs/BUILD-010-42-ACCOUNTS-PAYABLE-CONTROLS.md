# Build 010.42 — Enterprise Accounts Payable & Financial Controls

## Delivered
- Vendor bill register and duplicate bill-number uniqueness per vendor.
- Configurable approval rules with required role and approval count.
- Approver identity and decision ledger.
- Check/ACH payment proposals with future-date validation and duplicate active proposal prevention.
- Positive Pay preparation records with account last-four only.
- Manual bank transaction register and debit-to-proposal reconciliation.
- Bill status progression and finance dashboard.
- Restricted finance API, RLS, acceptance contracts.

## Important release boundaries
- Payment proposals do not transmit funds. No ACH, bank, check-printing, payment processor or financial institution integration.
- Positive Pay entries are not submitted to a bank. No bank file export exists.
- Bank transactions are manually recorded; no bank feed or statement import exists.
- Approval rules must be explicitly seeded and tested before use. The migration creates no default rule.
- Current approval RPC accepts role text from a server route; production must verify authoritative role assignment, distinct approver separation, self-approval prohibition, amount tiers and segregation of duties.
- Reconciliation matches debit amount within one cent and marks the bill paid. This is a manual accounting assertion, not proof of bank settlement; verify vendor, account, date, currency and bank source before matching.
- AP audit table is provisioned; this API version does not yet write an audit event for every operation.
- No GL posting, tax, accrual, cash forecasting or financial statement integration.

## Validation
Run `npm run test:build010:ap`, `npm run lint`, and `npm run build`. Apply migration in staging after Build 010.41. Test RLS, configured approval rules, duplicate bill prevention, approval identity, proposal dates, Positive Pay uniqueness and reconciliation exception paths. Not merged, migrated or deployed.
