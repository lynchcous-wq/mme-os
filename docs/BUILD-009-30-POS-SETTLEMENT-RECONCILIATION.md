# Build 009.30 — POS Payment Reconciliation & Settlement Integrity Intelligence Engine

Status: implementation committed to a review branch; migration replay, database integration, provider/bank adapters and financial control validation pending.

## Dependencies
- Build 009.20–009.26: POS hardware command/state, network and continuity controls.
- Build 009.27: security event and investigation foundation.
- Build 009.28: transaction anomaly and fraud event foundation.
- Build 009.29: processor dispute and chargeback lifecycle.
- Existing MME Payments Center, POS tender ledger, refund workflow, transaction journal and cash-drawer monitoring.

## Implemented database foundation
- `mme_pos_settlement_batches`: provider payout batches, gross/fees/net, location, currency and provider references.
- `mme_pos_settlement_lines`: normalized processor balance lines for charges, refunds, disputes, fees, adjustments, reserves and payouts.
- `mme_pos_reconciliation_runs`: repeatable reconciliation runs and aggregate matched/exception counts.
- `mme_pos_settlement_matches`: exact-reference or approved-manual matching with amount/currency comparison.
- `mme_pos_settlement_exceptions`: missing transactions/lines, amount/fee/currency mismatches, duplicates, refunds, disputes, late settlements and unexpected adjustments.
- `mme_pos_bank_deposits` and `mme_pos_settlement_bank_matches`: imported bank deposit references and settlement-to-deposit matching.
- `mme_pos_settlement_approvals`: independent approval decisions and reasons.
- `mme_pos_cash_drawer_closings`: expected/count cash, variance, witness and independent approval.
- `mme_pos_settlement_audit_events`: immutable-style operational audit records.

## Reconciliation workflow
1. A trusted Stripe/Verifone connector imports provider payout batches and balance lines. It verifies provider authentication, event identity, replay protection and source integrity before ingestion.
2. Normalize money to integer minor units and preserve ISO currency. Never aggregate different currencies without an explicit FX workflow and source rate.
3. Match each provider line to the authoritative MME transaction/tender ledger using provider payment/charge/refund references first. Transaction ID and amount/time are secondary matching evidence; ambiguous matches go to human review.
4. Reconcile charges, refunds, reversals, fees, disputes, dispute reversals, reserves and adjustments as distinct line types.
5. Reconcile batch gross, fees and net to the provider payout summary. Record mismatches as exceptions; do not silently post balancing adjustments.
6. Import bank statement deposit references from an approved finance connector and match the actual net payout to the bank deposit. A provider payout marked paid is not proof that the bank received the deposit.
7. Run reconciliation again after source corrections. Preserve previous runs and audit history.
8. Require an independent Finance approver. Approval is blocked while unmatched lines or unresolved exceptions remain.
9. Close the reconciliation only after authoritative processor and bank sources agree, or after a documented, separately authorized variance process.

## Cash drawer close
- Calculate expected cash as opening float + cash sales - cash refunds - paid-outs.
- Record counted cash and variance for each store/register/business date.
- Require a separate witness; the cashier cannot witness their own count.
- Require a separate approver from the person who counted.
- Correlate drawer open/close and hardware acknowledgment data from earlier Build 009 hardware components. A drawer command timeout is not itself a cash shortage.
- A variance triggers an exception and review task; it does not establish theft or employee misconduct.

## Financial integrity rules
- Use integer minor units; never floating point for money arithmetic.
- Batch net must equal gross less fees (plus explicit adjustments only where provider contract and schema support them).
- Enforce currency consistency across batch, line, POS transaction and bank deposit.
- Do not duplicate a transaction match within a reconciliation run.
- Do not infer a successful capture from an authorization, or a completed refund from a request alone.
- Do not retry an uncertain payment; reconcile with the processor first.
- Never use this build to initiate ACH, wire, payout, refund or bank transfers. It is a reconciliation/control system, not a funds-movement system.
- Do not store bank login credentials, full bank account numbers, PAN, CVV/CVC, PIN or track data. Store only approved account tokens/references and redacted descriptions.
- Dispute amounts must reconcile with Build 009.29; fraud flags from Build 009.28 are investigative context, not automatic write-offs.

## Authorization and security
- Settlement permissions: `pos.settlement.view`, `pos.settlement.reconcile`, `pos.settlement.exception.manage`, `pos.settlement.approve`, `pos.settlement.bank.match`, `pos.settlement.cash.manage`.
- Extend the shared Build 009 identity gate while preserving active identity, active employment, CEO freeze, unexpired permission grants and store scope.
- New tables enable RLS; direct public/anonymous/authenticated table access is revoked; trusted service role performs connector and worker operations.
- Manual matching and approvals require role checks and audit reasons.
- Finance data is store-scoped and restricted by role. CEO sees enterprise summaries; detailed bank references remain limited to authorized Finance users.

## Dashboard specification (not live)
- CEO: enterprise net settlement, store-level variance, unresolved exceptions, cash variance and reconciliation completion.
- Finance: processor batch gross/fees/net, bank deposit matches, pending settlement, refunds, disputes, unmatched transactions and approvals.
- Store Manager: local register cash close, deposit status and assigned exceptions only.
- IT/CIO: connector health, import lag, duplicate provider events, failed syncs and reconciliation worker status.
- Loss Prevention: authorized exception/case links only; no automatic misconduct labels.

## Validation required
Run:
- `npm run test:build009:settlement-integrity`
- `npm run test:build009:disputes`
- `npm run test:build009:fraud-intelligence`
- `npm run test:build009:payments`
- `npm run test:build009:reconciliation`
- `npm run test:build009:tenders`
- `npm run test:build009:refunds`
- All preceding Build 009 suites and `npm run lint`.
- Full ordered Supabase migration replay and PostgreSQL integration tests in an isolated environment.

Integration tests must cover duplicate payout imports, duplicate balance lines, missing POS transaction, missing processor line, amount/fee/currency mismatch, cross-store matching, repeated reconciliation, unresolved exception approval denial, independent approval, bank deposit mismatch, late settlement, cash arithmetic, cashier/witness conflict, count/approver conflict, uncertain processor payment, chargeback/refund correlation and audit completeness.

## Not claimed complete
No Stripe/Verifone or bank connector has been connected. No real settlement or bank statement has been imported. No bank deposit has been verified. No live cash close dashboard, reconciliation worker, notification engine or finance dashboard has been deployed. No migration has been applied to production Supabase. No money movement is initiated by this build.
