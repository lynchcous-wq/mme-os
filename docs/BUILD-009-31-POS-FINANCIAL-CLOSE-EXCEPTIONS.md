# Build 009.31 — POS Settlement Exception Resolution & Financial Close Automation Engine

Status: implementation committed to a review branch; migration replay, SQL integration tests, accounting policy review and application/worker integration pending.

## Dependencies
- Build 009.20–009.26: hardware dispatch/state, network security and continuity.
- Build 009.27: POS security events and evidence investigation.
- Build 009.28: transaction anomaly and fraud intelligence.
- Build 009.29: payment disputes and chargebacks.
- Build 009.30: processor settlement batches, balance lines, reconciliation runs, bank deposit matches, cash close and settlement approvals.

## Implemented database foundation
- `mme_pos_settlement_exception_history`: append-only assignment, status, investigation, evidence-reference and resolution history.
- `mme_pos_settlement_adjustment_requests`: evidence-backed proposed accounting corrections with independent review.
- `mme_pos_financial_closes`: store, period, currency and IANA business-timezone scoped financial close.
- `mme_pos_financial_close_items`: source snapshots for settlement runs, exceptions, bank deposits and register cash closings.
- `mme_pos_financial_close_events`: reasoned prepare, block, approval, close and reopen events.
- Build 009.30 shared authorization gate extended with close preparation, close approval and adjustment-request permissions.
- New tables use RLS; direct public/anonymous/authenticated table access is revoked and trusted service-role operations are required.

## Exception workflow
1. An exception enters the Finance queue from a settlement reconciliation run.
2. An authorized Finance user assigns an active, store-authorized employee and records a reason.
3. The assigned investigator checks source processor references, POS transaction records, refunds, fees, chargebacks, bank deposits and supporting documents.
4. Resolution requires a resolution code, explanatory notes and an evidence reference. The system records previous/new status, actor, time and evidence reference.
5. Accepted variance is a separate approval decision. The assigned investigator cannot accept their own exception variance; a separately authorized approver must approve.
6. Unresolved, assigned, investigating and escalated exceptions continue to block financial close.
7. False-positive closure requires an explicit reason and remains visible in history.

A resolved exception is not proof of employee wrongdoing or customer fraud. Cash variances and unusual transaction patterns are financial-control signals requiring review.

## Adjustment request workflow
- An authorized user submits a non-zero adjustment proposal with currency, type, reason and source evidence reference.
- A different authorized Finance approver approves or rejects the request.
- Approval records the proposed accounting treatment only. It does not alter a processor balance, create a payout, mutate the transaction ledger or post to the general ledger.
- A future accounting integration must separately validate account mapping, journal balancing, posting idempotency, period lock, reversal and independent posting approval before any ledger posting is enabled.

## Financial close workflow
1. A Finance user prepares a close for a store, UTC start/end instants, currency and the store's IANA business timezone.
2. The engine identifies all settled processor batches in the period and checks that each has an approved reconciliation run.
3. It checks all period exceptions, processor-to-bank matches, bank deposits not matched to any settlement, unapproved register cash closings and unresolved cash variances.
4. The close snapshot captures settlement runs, exception references, bank deposit references and cash-close references. Refresh replaces the derived snapshot atomically while the close is still unapproved.
5. The close is marked blocked if a batch is unreconciled, an exception is open, a bank deposit is unmatched, a cash close is unapproved, a cash variance remains unresolved, or matched bank deposits do not equal processor net settlements.
6. Only a ready close may be approved, by a person different from its preparer.
7. The recorded approver finalizes the approved close. The close is then locked against refresh.
8. Reopening a closed period requires an authorized actor and a detailed reason. The original close and its event history remain available.

The period is represented as timezone-aware timestamps. Register business dates are interpreted using the supplied IANA timezone, not a hard-coded UTC date conversion. The timezone must be sourced from the store configuration by the application; the migration does not infer a store's timezone.

## Financial integrity safeguards
- Use integer minor units and ISO currency codes. Never aggregate unlike currencies.
- Every settled processor batch in the period must have an approved reconciliation run.
- A bank deposit can be matched to only one payout batch in the initial matching model; if the bank combines multiple payouts, Finance must use a separately designed allocation workflow rather than reuse a deposit reference.
- Matched bank deposits are summed once; unmatched/orphan bank deposits block close.
- Accepted variance requires a separate approval and documented rationale.
- Cash variance approval requires a note explaining the variance. The cashier cannot witness their own count; the approver cannot be the cashier.
- No adjustment is auto-posted. No ACH, wire, payout, refund, capture or other movement of funds is initiated.
- Do not store PAN, CVV/CVC, PIN, track data, bank login credentials or raw account numbers.
- Processor and bank source imports remain trusted external connector responsibilities; this migration does not verify provider signatures or connect to live APIs.

## Authorization
- `pos.settlement.exception.manage`
- `pos.settlement.adjustment.request`
- `pos.settlement.close.prepare`
- `pos.settlement.close.approve`
- Existing `pos.settlement.view`, `reconcile`, `approve`, `bank.match` and `cash.manage` permissions remain.
- Shared authorization continues to require active identity, active employment, no CEO-wide employee-access freeze, unexpired grants and matching store scope. CEO enterprise override follows the existing shared gate.
- Service-role access is not a substitute for application authorization; trusted workers must validate the initiating actor and permission before invoking privileged routines.

## Dashboard specification (not live)
- Finance queue: exception type, severity, age, store, assignee, amount variance, evidence completeness and deadline.
- Adjustment review: requested amount, currency, source evidence, requester, reviewer and decision.
- Daily close: processor net, matched bank net, unsettled batches, unmatched deposits, open exceptions, cash variance and readiness.
- CEO: enterprise close status, stores blocked, unresolved material variance, close timeliness and historical trend.
- Store Manager: local register close tasks and assigned evidence requests only.
- Loss Prevention: authorized links to related investigations, without automatic employee-misconduct findings.

## Validation required
Run:
- `npm run test:build009:financial-close`
- `npm run test:build009:settlement-integrity`
- `npm run test:build009:disputes`
- `npm run test:build009:fraud-intelligence`
- All preceding Build 009 POS, payments, refunds, reconciliation and security suites.
- `npm run lint`
- Full ordered Supabase migration replay and PostgreSQL integration tests in an isolated database.

Integration tests must cover cross-store assignment denial, inactive assignee rejection, duplicate history protection, evidence reference requirement, self-acceptance of variance denial, adjustment self-approval denial, adjustment non-posting, IANA timezone/DST boundaries, missing settlement run, unresolved exception, unmatched bank deposit, orphan bank deposit, reused bank deposit rejection, bank net mismatch, cash close approval reason, unapproved cash close, unresolved cash variance, independent close approval, closed-period refresh denial, authorized reopen and audit completeness.

## Not claimed complete
No migration has been applied to production Supabase. No live Finance queue, scheduled close worker, bank/processor connector, notifications, general-ledger posting or CEO dashboard has been deployed. No adjustment has been posted and no funds have been moved. SQL contract tests have been added but have not been executed in this workflow.
