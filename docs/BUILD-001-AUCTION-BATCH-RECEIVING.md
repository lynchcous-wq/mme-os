# Build 001 — Approved Auction Batch Receiving & Activation

**Status:** Proposed additive migration; not applied.

## Serialized identifiers
A serialized import line must provide one unique serial number for every unit; IMEI is optional for non-phone devices. The trusted intake process stores these identifiers before CEO approval. Duplicate serials/IMEIs are rejected by the import table and again by the physical unit ledger.

## Atomic receiving
Only an approved batch can be received. The receiving RPC locks the batch, validates every line and product type, reconciles the acquisition amount, and creates one receipt header. Aggregate products are posted through the existing inventory receipt function; serialized products create one physical unit and one per-device landed-cost record per identifier. The batch is linked to the receipt and marked received in the same transaction. Repeated calls return the existing receipt instead of posting duplicate stock.

## Cost audit
Each source line receives an exact acquisition and additional-cost allocation record. The final line absorbs pool rounding cents. Aggregate allocations are also written to the existing landed-cost allocation ledger. Per-device costs are split across serials deterministically; residual cents are retained at line level for reconciliation.

## Controls and limitations
- The RPC is service-role only. The trusted server must independently authenticate the actor and verify CEO approval authority and location permissions.
- CSV parsing, document OCR and online retail research remain external trusted-worker integrations.
- Aggregate average unit cost stores whole cents per unit; line-level remainder is retained in the audit ledger and must be reconciled by accounting.
- This migration has schema tests but has not been applied to a database or executed against production data.