# Build 001 — receiving, adjustments, and transfers

**Status:** Proposed additive migration; not applied.

## Receiving
A receipt header records the source (auction pallet, supplier, customer return, other), receipt reference, purchase total, receiving actor, approver, and notes. Each receipt line increases location stock and updates weighted-average unit cost. Duplicate product/location lines are rejected; serialized products use the individual-unit intake path instead.

## Stock adjustments
The adjustment RPC supports positive and negative count corrections with a mandatory reason and actor. It refuses to reduce on-hand quantity below reserved stock. Optional unit cost updates the balance cost basis. Every movement records before/after on-hand and reserved quantities, cost, reference, actor, and approver.

## Transfers
The transfer RPC moves unreserved quantity between active store locations in one database transaction. Both sides share a transfer-group ID and retain the same average cost. If either side fails, both changes roll back. Serialized devices require an individual-unit transfer flow and are rejected here.

## CEO approval and permissions
All RPCs are service-role only; browser roles have no direct access. The trusted server must authenticate the employee and enforce MME role/CEO approval policy before calling them. The approver UUID is an audit attribution field, not proof of authorization. Do not expose service_role credentials. Approval thresholds and role checks must be enforced by the server adapter and audited.

## Costing boundary
Receipt line costs are weighted into location-level average unit cost. The receipt's purchase total is recorded as a source document value; landed-cost allocation across pallet line items (freight, fees, tax, per-item allocation) remains a separate CEO-controlled costing engine. Do not treat the raw purchase total as a per-unit cost unless the CEO's allocation engine has produced line-level costs.
