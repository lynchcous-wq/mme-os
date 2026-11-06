# Build 001 — Physical Stocktake & Inventory Reconciliation

**Status:** Proposed additive migration; not applied.

## Count sessions
Authorized staff can open a location-scoped blind or guided count. A blind count does not show expected quantities in the count-entry interface. The session snapshots expected aggregate quantities and weighted average cost for active, non-serialized products. Optional category scope is supported. Serialized devices remain in their separate unit ledger.

## Count workflow
Each product count records counted quantity, employee attribution, timestamp and optional note. Submission is blocked until every included product has a count. A separate authorized approver reviews the variance report and approves or rejects the session with a note.

## Reconciliation
Only an approved session can be applied. The apply operation compares counted quantities with current balances (not merely the opening snapshot) and writes differences through the existing inventory adjustment function, preserving the movement ledger and reserved-stock protection. If a change happened after the count opened, the adjustment is calculated against current stock so the final on-hand quantity reaches the approved physical count. Any reserved-stock conflict aborts the whole transaction.

## Controls and limits
Tables and RPCs are service-role only. The trusted server must verify employee roles, separate counter and approver duties where policy requires, and ensure the approver is genuinely authorized; identity UUID arguments are audit attribution, not authentication. This phase does not reconcile serialized unit identities, perform scanner integration, or handle blind recount/dispute workflows. Test on a disposable database for incomplete submissions, duplicate references, approval gating, concurrent movements, reserved quantity conflicts and transaction rollback.
