# Build 010.56 — Treasury Management & Cash Flow Operations

## Canonical source-of-truth protection
This build extends the existing Build 010.46 treasury implementation and its bank-account, statement, transaction, matching, reconciliation and audit tables. It does not create a parallel bank-account or bank-transaction ledger.

## Added
- Deposit evidence records linked to canonical bank accounts.
- Outstanding check register with cleared, void and stop-payment states.
- ACH event evidence register.
- Internal cash transfer requests with submitter and independent approver separation.
- Base, upside and downside cash forecast snapshots with generated projected closing cash.
- Treasury API endpoints and forms for deposit/check/ACH/transfer/forecast records.
- Updated dashboard status labels and acceptance tests.
- RLS and service-role-only access for extension tables.

## Operational and production boundaries
- Bank statement import remains structured JSON/manual import. No live bank connection, credential storage, bank polling or automatic bank-feed ingestion.
- ACH events are manually recorded evidence. No ACH origination, release, settlement verification or bank integration.
- Internal cash transfer approval does not move money; no payment rail or execution worker is included.
- Deposit/check/ACH evidence is not proof of bank clearing. Independent statement reconciliation remains required.
- Forecasts are user-entered snapshots, not a rolling forecast automatically calculated from POS, payroll, AP, AR, inventory and bank feeds.
- Role authorization uses the current treasury role allowlist. Production requires entity/store-level scope, separation-of-duties review, audit monitoring and security review.
- The prior Build 010.46 treasury migration must be applied before this additive extension migration.

## Validation
Run `npm run test:build010:treasury-cash-operations`, `npm run test:build010:treasury`, `npm run lint`, and `npm run build`. Apply migrations in staging in order and validate statement import, duplicate handling, GL match direction/amount, reconciliation exceptions, transfer self-approval rejection, cross-entity access, and cash forecast arithmetic. Not merged, migrated or production deployed.
