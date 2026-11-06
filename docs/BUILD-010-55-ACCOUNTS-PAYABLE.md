# Build 010.55 — Vendor Management & Accounts Payable

## Added
- Vendor onboarding verification status and vendor document register.
- AP invoice intake records with vendor invoice uniqueness, due dates, discounts and PO linkage.
- Match evidence records for invoice, PO and receipt amounts.
- AP match decision RPC with variance evidence.
- Independent invoice approval RPC.
- Payment schedule records with independent approval decision records.
- AP aging view with current, 1–30, 31–60, 61–90 and 90+ buckets.
- Finance API and executive dashboard read surfaces.
- RLS/service-role-only table access and acceptance tests.

## Production limitations / release gates
- Document storage path is metadata only; no secure upload, malware scanning, signed download, retention or access workflow.
- No OCR/email ingestion, invoice line-item extraction, tax validation or duplicate-content detection beyond vendor+invoice-number uniqueness.
- Match RPC records supplied amounts; it does not independently verify receiving records or PO line quantities, so this is evidence capture, not a fully automated three-way match.
- AP aging subtracts paid schedule amounts, but payment status is not automatically synchronized to bank settlement.
- Payment approval is a single independent reviewer; no thresholds, dual authorization, payment batch, ACH/check/wire release or bank integration.
- Payment schedules do not reserve invoice balances or prevent aggregate overpayment. Add transactional outstanding-balance enforcement before production.
- No GL posting, budget encumbrance, vendor tax/KYB screening, W-9 validation or bank account custody.
- Service-role endpoints require fine-grained finance permissions and entity/store scope controls before production use.
- Validate dependencies on procurement vendor and PO tables in staging.

## Validation
Run `npm run test:build010:accounts-payable`, `npm run test:build010:expense-procurement`, `npm run lint`, and `npm run build`. Migration not applied, tests not executed, not merged or production deployed.
