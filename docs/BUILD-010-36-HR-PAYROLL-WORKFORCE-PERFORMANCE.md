# Build 010.36 — HR, Payroll & Workforce Performance Integration

## Delivered
- Effective-dated compensation profile ledger with hourly, salary, commission-only and hybrid pay types.
- Time entry submission and manager review ledger.
- Payroll period and earning-line staging for regular, overtime, commission, bonus, adjustment and deduction.
- Commission ledger with verification and approval statuses.
- Performance review records with rating, strengths, improvement plan and goals.
- Workforce shift scheduling records.
- HR/payroll audit ledger.
- Authenticated HR/payroll administration API and dashboard.

## Financial and integration boundaries
- No tax calculation, withholding, ACH, check printing, direct deposit, payroll provider submission or tax filing occurs in this build.
- No production commission plan is automatically calculated from POS transactions; imported sale references and amounts require verification.
- Time entries are ledger submissions; this build does not assert hardware clock authentication, geolocation validation or automatic overtime compliance.
- Payroll line items require reconciliation against the approved compensation plan and jurisdictional payroll rules.
- Person identifiers and role claims require staging verification against canonical MME identity records.

## Validation and rollout
- Run `npm run test:build010:hr-payroll`, `npm run lint`, and `npm run build`.
- Apply migration in staging after Build 010.35; verify RLS, service-role grants, person identity references, precision/rounding and audit persistence.
- Not merged, migrated or production deployed.
