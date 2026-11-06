# Build 010.43 — Enterprise General Ledger & Accounting

## Delivered
- Chart of accounts with starter retail account codes.
- Open/closed/locked accounting period register.
- Double-entry journal header and line ledgers.
- Atomic journal posting RPC: open-period validation, balanced debits/credits, active account validation, immutable posted line capture and audit event.
- Period close RPC and audit event.
- Trial balance, income statement and balance sheet foundation views.
- Authenticated finance API, dashboard and acceptance contracts.

## Release boundaries
- Starter chart is illustrative; CFO/accountant must approve account mapping and opening balances.
- Financial views reflect only this GL's posted journal lines. POS, Stripe, inventory, payroll, AP and tax source systems are not automatically synchronized or reconciled.
- No automated revenue recognition, AR, tax, depreciation, bank feeds, consolidation, cash flow statement, retained earnings year-end close or statutory filing.
- Period close is irreversible through this UI; reopening workflow not provided.
- Posted journal entries are not editable; correction/reversal workflow must be implemented before live accounting operations.
- Production authorization needs explicit accountant/poster/reviewer separation and period-close permissions.
- Trial balance view currently presents aggregate debit and credit totals; statement reporting needs validated period filters, account mapping, opening balances and retained earnings handling.

## Validation
Run `npm run test:build010:gl`, `npm run lint`, and `npm run build`. Apply migration in staging after Build 010.42; test balanced/unbalanced journals, duplicate references, closed periods, concurrency, account deactivation and statement tie-out. Not merged, migrated or production deployed.
