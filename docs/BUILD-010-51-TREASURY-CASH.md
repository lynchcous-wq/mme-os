# Build 010.51 — Treasury Cash Management

## Existing foundation preserved
Extends the Build 010.46 treasury account/statement/transaction/GL matching/reconciliation dashboard and schema. No replacement bank ledger was created.

## Added in this build
- Deposit ledger with source references and clearing status.
- Outstanding check register and lifecycle status.
- ACH event evidence register with return codes.
- Internal cash-transfer records.
- Transfer submission and independent approval/rejection RPCs.
- Base/upside/downside cash forecast snapshots with generated closing-cash calculation and separately disclosed restricted cash.
- Authenticated treasury API actions and dashboard read panels.
- RLS and service-role-only access for new treasury tables.
- Acceptance contract tests.

## Production boundaries
- No live bank feed, Plaid/Finicity integration, credential collection or automatic statement polling.
- ACH events are manually recorded evidence; no ACH origination, bank instruction, payment provider submission or settlement confirmation.
- Check register is not a check-printing or Positive Pay bank transmission integration.
- Deposit entries do not prove funds cleared.
- Cash transfers are internal records and approval evidence only; they do not initiate movement of funds.
- Forecasts are manually supplied scenarios, not connected to AR/AP/payroll/POS actuals or automated projections.
- Approval RPC enforces submitter/reviewer separation for one approval step; configurable thresholds, multi-step approval, business-unit scoping and verified finance role policy remain required before production.
- The existing treasury service-role API has broad finance-role read access; add row-level organization/store scope before production.
- Confirm the treasury migration is applied after GL and Build 010.46 treasury foundation migrations.

## Validation
Run `npm run test:build010:treasury-cash`, `npm run test:build010:treasury`, `npm run test:build010:cashflow`, `npm run lint`, and `npm run build`. Apply migration in staging only after dependency checks. Test deposits, check lifecycle, duplicate ACH events, transfer approval separation, RLS, cash forecast arithmetic and no-funds-movement guarantee. Not merged, migrated or production deployed.
