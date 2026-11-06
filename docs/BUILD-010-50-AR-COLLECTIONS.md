# Build 010.50 — Accounts Receivable, Reconciliation & Collections

## Existing foundation preserved
The existing Build 010.44 AR billing module remains in place: invoices, payment allocation, credit memos, aging views, reminders, authenticated finance API and dashboard. This build extends that module; it does not create a second invoice ledger.

## Added
- Provider transaction evidence ledger for Stripe, bank, POS and manual imports.
- Unique provider event and transaction references to reduce replay/duplicate ingestion.
- Payment reconciliation ledger with a unique provider-transaction mapping.
- Reconciliation RPC validates amount, currency, customer and external reference, locks both records and writes audit evidence.
- Stripe subscription reference links and billing cadence metadata.
- Collection case management with priority, owner, next action and promise-to-pay fields.
- Unique active collection case per invoice.
- Collection activity history.
- Configurable reminder policy metadata.
- Expanded finance API and dashboard read views.
- RLS and service-role-only table access for new tables.

## Production boundaries / release blockers
- Provider import API is an authenticated manual evidence-entry endpoint, not a Stripe webhook receiver or bank-feed connector. It does not validate provider signatures or pull external data.
- No Stripe invoice/subscription synchronization, Stripe Billing integration, idempotent webhook event processor or automatic payment capture.
- Reconciliation is an exact-match control for amount/currency/customer/reference, not a settlement guarantee. Exceptions and partial/multi-invoice allocations need a dedicated workflow.
- Collection case and activity tables are available, but no UI workflow yet creates/assigns cases or records activity from the dashboard.
- Reminder policy table is configuration metadata; no scheduler/notification dispatch is wired. Queueing a reminder is not delivery.
- No credit-memo application workflow; issued credits do not automatically reduce open invoice balance.
- Existing AR schema uses customer UUID references without foreign keys to a verified canonical customer identity table. Confirm customer identity integration and migration ordering.
- Service-role backend currently allows broad AR finance-role read access; enforce row-level business-unit and customer scope before production.
- Do not mark a payment settled solely because a provider transaction was imported or matched.

## Validation
Run `npm run test:build010:ar-collections`, `npm run test:build010:ar`, `npm run lint`, and `npm run build`. Apply migration in staging after the Build 010.44 AR migration. Validate duplicate webhook/event ingestion, mismatches, partial allocation, credit application, collection-case concurrency, RLS, finance role isolation and Stripe test-mode reconciliation. Not merged, migrated or production deployed.
