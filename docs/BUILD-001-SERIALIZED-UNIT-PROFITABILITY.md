# Build 001 — Serialized Device Landed Cost & Profitability

**Status:** Proposed additive migration; not applied.

## Per-device cost basis
Each IMEI/serial-controlled unit can receive one immutable landed-cost record with acquisition, freight, auction fee, handling and other costs in USD cents. The unique unit constraint prevents duplicate cost basis entries. The source reference links the cost to the auction, pallet or receiving paperwork.

## Sale profitability
After the serialized unit has been marked sold by the trusted checkout workflow, the trusted order/payment service records one sale outcome linked to the order. The report calculates net revenue after discounts and refunds and realized gross profit after subtracting the device landed cost. Payment fees and other direct costs are separately reported and are not silently mixed into gross profit. Margin is realized gross profit divided by net revenue.

## Privacy
The report displays only the last four IMEI digits; full serial/IMEI values remain in the protected unit ledger. All tables and RPCs are service-role only.

## Integration boundary
The existing serialized intake function remains unchanged. The application server must record per-unit cost after receiving the unit and must call the sale-outcome RPC only after it independently verifies successful payment settlement and the unit's sold status. The RPC's actor UUID is attribution, not authentication. This migration does not itself connect payment events, update order status, process refunds or trigger cost creation.

## Reconciliation
One cost record and one sale outcome per device are enforced. Accounting should reconcile device cost, order line price, discounts, refunds and payment fees against the authoritative order and payment ledger.