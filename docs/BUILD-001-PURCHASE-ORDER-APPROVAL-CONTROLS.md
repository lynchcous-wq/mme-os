# Build 001 — Purchase Order Approval Controls

**Status:** Additive migration committed; not applied.

Strengthens the existing purchase-order state machine. The person who creates a PO cannot approve that same PO. Rejections and cancellations require a documented reason. Valid state transitions and immutable event history are retained. The service-role-only RPC remains inaccessible to browser roles.

Security boundary: UUID arguments are audit attribution, not authentication. The trusted application server must verify the acting employee identity and CEO-level purchasing permission before invoking approval. This migration does not itself establish an approval limit or authenticate a CEO.