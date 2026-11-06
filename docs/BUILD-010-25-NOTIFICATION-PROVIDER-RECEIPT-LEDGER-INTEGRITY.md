# Build 010.25 — Receipt Ledger Integrity & Monotonic Reconciliation

## Implemented
- Adds a durable, RLS-protected provider receipt event ledger for the escalation-channel delivery pipeline.
- Enforces provider/event idempotency with a unique key.
- Validates provider, channel, status, event ID, and provider reference before ingestion.
- Uses exact provider + channel + provider-reference correlation.
- Retains unmatched receipts and explicitly marks ambiguous references instead of selecting an arbitrary delivery.
- Makes delivered status monotonic: a late failure, queued, or sent callback cannot downgrade a delivery already marked delivered.
- Reconciles the parent dispatch only when every required channel is terminal.
- Restricts the ingestion RPC to the Supabase service role.

## Verification
Run `npm run test:build010:receipt-integrity` and the existing Build 010 receipt reconciliation suites.
Apply the migration in a non-production Supabase environment first. Confirm the existing escalation delivery tables and acknowledgement function signatures before production migration.

## Release gate
This change is committed to a feature branch and proposed as a draft pull request. It is not merged, migrated, or production-deployed. Vercel's existing Hobby cron limitation remains a separate production blocker.
