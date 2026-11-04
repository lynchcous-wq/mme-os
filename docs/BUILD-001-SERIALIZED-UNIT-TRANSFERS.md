# Build 001 — Serialized Device Transfers & Status History

**Status:** Proposed additive migration; not applied.

## Individual device movement
Every serialized device transfer is tracked separately by unit ID, source location, destination location, status, reason, reference, actor and approver. Batch transfer requests are atomic: one invalid unit causes the entire batch to roll back. Only in-stock units may transfer; reserved and sold devices must use their dedicated order/return workflows.

## Device status control
In-stock devices may be placed into repair or quarantine. Repair/quarantine units may be returned to in-stock through the controlled status RPC. Releasing a quarantined device requires an approver attribution. Sold and reserved states cannot be changed through this general-purpose function.

## Audit and security
The immutable movement ledger is service-role only. The trusted application must authenticate actors, verify store-level access, enforce manager/CEO approval rules and prevent a caller from self-assigning an approver identity. No browser service-role credentials.

## Integration
The inventory UI should show serial-level transfer selection, destination confirmation, reason/reference, approval, and device movement history. This migration adds backend contracts; it does not create a scanner UI, device connection, or production deployment.