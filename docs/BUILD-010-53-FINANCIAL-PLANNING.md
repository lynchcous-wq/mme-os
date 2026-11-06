# Build 010.53 — Enterprise Budgeting, Forecasting & Financial Planning

## Source of truth preserved
Extends existing GL, financial reporting and consolidation records. Budget plans are distinct from posted accounting actuals; no duplicate journal ledger is created.

## Added
- Fiscal-year budget headers with version numbers, entity scope, currency and draft/submitted/approved/locked lifecycle.
- Budget lines by period, account, department, store and category.
- Submit and independent reviewer approval functions.
- Base, upside, downside and custom forecast scenarios.
- Forecast lines with driver assumptions and explicit source labels.
- Actual snapshot evidence with source system and watermark.
- Revenue, payroll, inventory, expense and cash planning driver register.
- Authenticated GL API read/actions and finance dashboard panels.
- RLS and service-role-only access for new tables.
- Acceptance contract tests.

## Production boundaries
- Budget and forecast values are manually entered in this build. No automated POS sales, payroll, inventory purchasing, AR/AP, bank or GL actuals ingestion.
- Forecast lines do not calculate a complete financial forecast from drivers; scenario math and dependency graph are not yet implemented.
- Actual snapshots are not automatically tied to the posted GL trial balance. Avoid presenting them as audited actuals.
- Approval workflow is a single independent reviewer step; configurable thresholds, multi-step approvals and entity/store scope enforcement remain release gates.
- No budget variance automation, budget lock enforcement on line mutation, version-copy workflow, or budget-vs-actual dashboard calculation yet.
- No payroll commitment, inventory replenishment or purchase order is created from a forecast.
- Confirm entity and account-code references against canonical MME data before staging migration.
- Service-role API must receive business-unit/store-level authorization before production.

## Validation
Run `npm run test:build010:financial-planning`, `npm run test:build010:financial-reporting`, `npm run lint`, and `npm run build`. Apply migration in staging after reporting-entity schema is present. Test version uniqueness, approval separation, date boundaries, negative/positive budgets, scenario isolation, source lineage, RLS and cross-store access. Not merged, migrated or production deployed.
