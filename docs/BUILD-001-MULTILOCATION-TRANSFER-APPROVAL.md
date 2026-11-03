# Build 001 — Multi-Location Transfer Approval Workflow

**Status:** Additive migration committed; not applied.

Adds a two-person workflow for moving aggregate stock and serialized devices between active store/warehouse locations. Employees submit a transfer request with source, destination, quantity or exact device IDs, reason and requester identity. A different employee/authorized approver must approve or reject. Self-approval is blocked at the database layer.

No inventory quantity or device location changes when a request is submitted. Approval invokes the existing atomic aggregate or serialized transfer function inside the same database transaction. The request stores the transfer group ID for reconciliation. Rejections require a reason.

The RPCs are service-role only. The trusted API must authenticate the human actor and independently enforce MME role, location scope and approval authority; passing an identity UUID alone is not authentication. CEO/authorized approver policy remains in the server authorization layer. Failed transfer execution rolls back the approval decision and inventory mutation together.

This migration does not create an automatic transfer recommendation algorithm; it provides the controlled approval and execution foundation.