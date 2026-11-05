# Build 009.34 — POS Financial Data Source Connector & Import Orchestration Engine

Status: implementation committed to a review branch. Database replay, automated tests, live provider credentials and provider-specific integration validation remain pending.

## Purpose
Provide a controlled, store-scoped ingestion layer between MME source systems and the immutable Build 009.32 financial fact ledger. Normalize approved source records, stage batches, deduplicate, quarantine invalid/conflicting records and expose auditable connector status.

## Delivered files
- `supabase/migrations/20261105001140_build009_pos_financial_source_connectors.sql`
- `app/api/pos/financial-connectors/route.ts`
- `app/internal/financial-connectors/page.tsx`
- `tests/build009-pos-financial-source-connectors.test.mjs`
- `package.json`: `npm run test:build009:financial-connectors`
- `app/globals.css`: responsive connector workspace styling

## Connector types and source mapping
- POS transaction source → `pos`
- Stripe/payment processor → `payments`
- Inventory/COGS source → `inventory`
- Subscription billing source → `subscriptions`
- Bank feed and approved manual imports → `manual_import`

The database stores connector metadata and an external secret-vault reference only. It never stores provider API secrets, bearer tokens, card numbers, CVV/CVC, PIN, track data or raw provider payloads. Credentials must be provisioned in an approved external secret manager with least-privilege scopes and rotation.

## Data pipeline
1. Authorized administrator registers a connector against one store.
2. Connector remains pending until an authorized administrator activates it with a secret-vault reference.
3. Approved provider adapter maps source data into the strict normalized financial fact schema.
4. Authenticated importer stages 1–250 allowlisted rows with source batch ID and idempotency key.
5. The import worker processes each row through the existing Build 009.32 `mme_pos_import_financial_fact` function.
6. Identical source facts are counted as duplicates; conflicting source content and invalid rows are quarantined with safe diagnostics.
7. A batch ends as completed or completed_with_quarantine. Failed/invalid rows are not silently discarded.
8. Source cursor advancement is exposed as a database function and is permitted only after a terminal batch status.
9. A subsequent Build 009.32 report build creates a new immutable snapshot; imports never rewrite prior reports.

## Database additions
- `mme_pos_financial_connectors`: store-scoped provider metadata, status and external secret reference.
- `mme_pos_financial_import_batches`: idempotent batch metadata and row counts.
- `mme_pos_financial_import_rows`: allowlisted normalized records and per-row outcomes.
- `mme_pos_financial_import_quarantine`: rejected rows and review state.
- `mme_pos_financial_import_cursors`: source pagination checkpoint.
- `mme_pos_financial_connector_events`: append-only lifecycle and import audit events.

Functions:
- `mme_pos_register_financial_connector`
- `mme_pos_set_financial_connector_status`
- `mme_pos_stage_financial_import_batch`
- `mme_pos_process_financial_import_batch`
- `mme_pos_advance_financial_import_cursor`

## API and user interface
Route: `/internal/financial-connectors`

- GET returns connector registry, recent batches and open quarantine for an authorized store.
- POST actions register_connector, set_connector_status, stage_batch and process_batch.
- Every request verifies an employee Supabase session and resolves the MME person identity.
- Store-scoped permissions: `pos.finance.connector.view`, `pos.finance.connector.manage`, `pos.finance.report.import`.
- RLS enabled; direct public, anon and authenticated table access revoked; service-role access remains server-side.
- UI supports connector registration, activate/pause/reactivate/revoke, normalized batch staging, processing and quarantine visibility.
- Token remains in component memory only. Manual token entry is a temporary bridge pending integration with the employee session provider.

## Integrity and safety rules
- Batch idempotency key and source batch reference are unique per connector.
- A source line and fact type cannot be staged twice within a batch.
- Financial facts continue to use the existing append-only import function, source-reference uniqueness, currency/timezone validation and closed-period protection.
- Per-row processing uses an isolated exception block so a malformed row can be quarantined while other valid rows proceed.
- Connector cursor cannot advance before the batch reaches completed or completed_with_quarantine.
- No payment capture, refund, payout, bank transfer, accounting journal posting or cardholder-data processing occurs.
- Source amounts and accounting mappings require Finance review; imported values are not automatically certified as ledger truth.

## Explicit integration boundary
This change implements connector registry, normalized import contracts, batch processing and administrative UI. It does **not** yet implement live Stripe webhooks/API polling, a POS vendor adapter, inventory platform API integration, subscription platform API integration, bank feed OAuth, background schedules, automatic retries, cursor polling workers, or provider signature verification. Those require approved provider-specific scopes, source mappings, secrets, webhook verification, environment configuration and integration tests. Do not mark a connector live merely because its metadata record exists or its status is active.

## Validation required
Run:
- `npm run test:build009:financial-connectors`
- `npm run test:build009:financial-reporting`
- `npm run lint`
- `npm run build`
- Ordered Supabase migration replay from the current production baseline.
- PostgreSQL integration tests for permission denial, cross-store access, duplicate batch IDs, duplicate rows, conflicting facts, malformed amounts, closed periods, quarantine and cursor advancement.
- Provider sandbox tests and security review before activating any live provider adapter.

No live provider connection, successful data import, production migration or deployment is claimed.
