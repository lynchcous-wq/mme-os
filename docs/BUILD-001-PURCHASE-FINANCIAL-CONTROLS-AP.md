# Build 001 — Purchase Financial Controls & Accounts Payable

**Status:** Proposed additive migration; not applied.

## Purchase budget gate
Each location can have an effective monthly purchasing budget, maximum PO amount and approval threshold. A PO cannot transition to approved without an active location policy. The approval trigger checks the PO's location, maximum amount and month-to-date approved/issued/received commitments. A PO spanning multiple locations is blocked for separate allocation and approval.

## Invoice approval
Invoices must pass the existing PO invoice match before approval. The requester and decision-maker must be different identities. Approval, rejection or hold is recorded with amount and match-status snapshots. The trusted service must verify actual role and purchasing authority; UUID attribution is not authentication.

## Accounts payable
Only matched and approved invoices can create a payment schedule. The payable amount is snapshotted from the invoice total and requires a due date and payment method. Payment events are idempotent by provider/event ID, preserve external references, and update the schedule to processing, paid, failed or on hold. Settled/reconciled amounts must equal the scheduled amount; partial payments and split schedules require a future allocation ledger.

## No false payment claims
This schema does not initiate ACH, wire, check, card or Stripe transfers. A paid state can only be recorded from a trusted, verified settlement/reconciliation event. Bank or payment provider integration and webhook signature validation remain separate implementation work.

## Security and verification
All financial tables and RPCs are service-role only. The trusted backend must enforce identity, role, location scope, approval thresholds, webhook signatures and reconciliation permissions. Run disposable database tests for missing budgets, max PO and monthly budget breaches, self-approval, unmatched invoice holds, duplicate provider events, wrong settlement amounts and payment reversal before merge.