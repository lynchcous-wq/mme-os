# Build 009.45 — Stripe Settlement Exception Intelligence

## Purpose
Detect and prioritize refund-related gaps between MME's completed refund requests and imported Stripe payout lines, then route them through an auditable Finance exception lifecycle.

## Detection
The batch-scoped detector identifies:
- Stripe refund payout lines without a corresponding completed MME refund request.
- Completed MME Stripe refunds that remain unmatched after a configurable 1-hour to 30-day grace period.
- Existing refund settlement mismatches, including amount, currency and connected-account differences.
- Refunds whose financial facts are blocked by a closed period or conflicting source content.

The detector is idempotent by source case and exception type. Repeated scans do not create duplicate cases. Detection does not alter provider or financial source records.

## Case management
- Store-scoped permission: `pos.settlement.exception.manage`.
- Assign only active employees.
- Move cases into investigation.
- Resolve, accept variance or mark false positive only with a resolution code and evidence notes.
- Critical cases require the separate `pos.settlement.approve` permission to close.
- Reopen closed cases with an immutable event trail.
- SLA due times are severity-based; an explicit escalation operation advances escalation level up to three and writes an audit event.

## Dashboard
The service-role dashboard groups cases by location, currency, status, severity and exception type. Exposure is shown in integer minor units; totals across currencies must never be combined. Overdue and unassigned counts support Finance workload management and CEO visibility.

## RPCs
- `mme_pos_detect_stripe_settlement_exceptions(batch_id, actor_person_id, missing_refund_grace)`
- `mme_pos_manage_stripe_settlement_exception(case_id, actor_person_id, action, assignee_person_id, resolution_code, notes)`
- `mme_pos_escalate_stripe_settlement_exceptions(location_id, actor_person_id)`

## Rollout and validation
Run `npm run lint`, `npm run test:build009:stripe-settlement-exceptions`, and the existing Stripe refund settlement, refund, settlement integrity and financial reporting suites. Perform ordered migration replay and PostgreSQL integration tests for repeated scans, missing refunds, account/amount/currency mismatch, closed periods, concurrent assignment, unauthorized users, critical-case approval, SLA escalation and reopen/resolution event history.

Implementation branch only. No production migration, scheduled scan, live provider operation or dashboard deployment is claimed. Configure a restricted scheduler only after CI and sandbox validation.
