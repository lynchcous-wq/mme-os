# Build 001 — Customer Returns, Refund Approval & Inspection Intake

**Status:** Proposed additive migration; not applied.

## Return authorization
Return cases link to completed paid orders and their original order lines. Quantity checks prevent returning more units than were purchased across all non-rejected/non-cancelled return cases. Serialized units require quantity one and retain serial/IMEI snapshots; a unit cannot be entered into a second active return.

## Receiving and inspection
Only authorized/in-transit RMAs can be received. Receipt moves lines to inspection-pending, not sellable stock. The existing inspection workflow remains the authority for condition grading, evidence, repair, quarantine, write-off and return-to-stock decisions. Returned items are never automatically restocked.

## Refund approval and provider evidence
Refund approval is independent of return intake. Requester and decision-maker must differ; approved amount cannot exceed returned line value or original order total. Provider events are idempotent and must match the exact approved amount/currency. The trusted payment adapter must verify provider signature, account, environment, refund ID, event semantics and original charge linkage before recording a success.

## Boundaries
This migration records refund authorization and verified provider outcomes; it does not call Stripe, initiate money movement, or automatically mark a refund as paid. Partial refunds can be supported through a separate allocation ledger in a later enhancement. Backend authorization must verify actual identity, roles, store scope and approval authority; supplied UUIDs are audit attribution, not authentication.

## Verification
Run disposable-database integration tests for unpaid orders, excess quantities across multiple RMAs, serialized duplicate returns, unauthorized receipt, refund self-approval, refund over cap, duplicate provider events, mismatched amount/currency and inspection-only restock.