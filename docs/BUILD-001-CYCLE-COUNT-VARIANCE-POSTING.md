# Build 001 — Cycle Count Review & Variance Posting

**Status:** Proposed additive migration; not applied.

## Submission
When a count is submitted, any remaining unscanned lines are explicitly recorded as zero counted. This supports both aggregate quantity counts and serialized-unit presence checks. The trusted app must make this behavior clear to the operator before submission.

## Independent approval
A different identity from the count opener must approve the submitted count. The trusted server must additionally verify that this identity has CEO/manager approval authority for the location. Identity UUIDs are audit attribution, not proof of authorization.

## Posting
Approved aggregate variances post through the existing inventory adjustment RPC, preserving before/after quantities, average cost and movement history. A missing serialized unit that was in stock is moved to quarantine rather than deleted. A missing serialized unit with an active reservation blocks the entire transaction. Found serialized devices remain individually tracked.

## Idempotency and atomicity
The session row is locked. Posted sessions return without applying a second adjustment. Any failed adjustment rolls back the entire posting transaction. The posting result and approver attribution are retained in the count event log.

## Controls
No client-side direct database access. Service-role functions require a trusted backend authorization layer for employee identity, role, location scope and approval threshold. Disposable PostgreSQL integration tests must cover positive/negative aggregate variances, reserved-stock floor, missing serial quarantine, independent approval, repeated posting and rollback.