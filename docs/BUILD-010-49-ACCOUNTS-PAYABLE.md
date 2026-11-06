# Build 010.49 — Accounts Payable & Vendor Payment Management

## Delivered in this repository branch
- Vendor directory and remittance metadata foundation.
- Purchase orders and line items.
- Invoice register, vendor/invoice duplicate uniqueness and due-date validation.
- Receipt evidence ledger.
- Invoice line and two-/three-way match result structures.
- Independent invoice approval function; submitter cannot approve own invoice.
- Payment schedule records and event/audit ledger.
- Payment scheduling capped at invoice total.
- Restricted finance API and AP dashboard.
- RLS enabled and direct client table access revoked.

## Important integration boundaries
- The existing AP route and page in this branch use the repository's existing bill/proposal/Positive Pay schema (Build 010.42 lineage), while the new migration adds the vendor/invoice/PO schema. The two schema generations are not yet unified. Do not assume this migration powers the existing dashboard.
- No OCR, email invoice ingestion, private receipt/document upload, malware scanning, or vendor verification workflow.
- No implemented automated PO/invoice/receipt quantity and price comparison engine. Match results table is a record structure, not proof that three-way matching has run.
- No multi-step approval engine or amount-threshold policy enforcement.
- Payment scheduling is an internal record only; no ACH, wire, check printing, card charge or funds transfer is initiated.
- Vendor remittance secrets must be stored in a dedicated encryption/secrets service; only a reference belongs in this database. No bank credentials or full account numbers should be stored here.
- No verified bank feed or automated payment settlement integration.
- Production role mapping, least-privilege vendor scope, separation of duties and migration compatibility must be tested.

## Validation
Run `npm run test:build010:ap-vendor`, `npm run lint`, and `npm run build`. Apply migration after earlier finance migrations in staging. Test duplicate invoices, due-date/amount constraints, independent approval, schedule caps, RLS, role isolation and compatibility with existing AP schema. Not merged, migrated or production deployed.
