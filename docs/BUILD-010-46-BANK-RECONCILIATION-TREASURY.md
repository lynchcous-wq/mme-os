# Build 010.46 — Bank Reconciliation & Treasury Management

## Delivered
- Masked bank-account registry linked to GL cash accounts.
- Bank statement header and transaction ledgers.
- Structured JSON statement import with date and row validation.
- Bank-to-posted-journal matching controls and match audit.
- Statement closing balance vs supplied GL closing balance reconciliation.
- Unmatched transaction exception status.
- Finance-role authenticated API, treasury dashboard and acceptance contracts.
- RLS and service-role-only data/RPC access.

## Release boundaries
- No live bank connectivity, Open Banking/OAuth, Plaid, direct bank API, SFTP, scheduled bank statement fetch or credential storage.
- No payment initiation, ACH origination, check issuance or wire transfers.
- No direct Stripe payout API adapter or automatic payout-to-bank matching. Stripe payouts must arrive through a separately verified source feed.
- Statement import accepts structured JSON only; CSV/OFX/QFX parser and bank-specific normalization remain future work.
- Import does not independently validate statement control totals against the sum of transaction rows, currency against the bank account, or cross-statement duplicate external IDs. Reconcile source statement totals manually before relying on results.
- Match workflow is one bank transaction to a posted GL journal entry, not split/multi-transaction or many-to-many matching. Full amount match is required.
- Reconciliation accepts a GL closing balance supplied by an authorized user; it does not independently derive a date-filtered bank-account ledger balance. Independent reviewer sign-off and segregation of duties remain required.
- No bank fee, interest, transfer, NSF, chargeback or FX adjustment journal generation.
- A matched transaction is not evidence of cleared funds or independent bank confirmation.
- Treasury accounts require existing GL account UUIDs; no account discovery UI is included.
- Production use requires bank data handling assessment, import provenance, duplicate detection, balance-control checks, reviewer approval, and tested backup/recovery.

## Validation
Run `npm run test:build010:treasury`, `npm run lint`, and `npm run build`. Apply migration after Builds 010.43–010.45 in staging. Test statement import, duplicate rows, invalid date/currency, partial/mismatched matches, concurrent matching, unmatched exceptions, reconciliation difference and RLS. Not merged, migrated or production deployed.
