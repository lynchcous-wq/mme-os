# Build 009.54 — Enterprise Inventory Recovery & Returned Asset Reconditioning

## Purpose
Connect approved returns to warehouse quarantine, refurbishment, asset-level cost accounting, resale classification and an idempotent inventory handoff.

## Lifecycle
Return item -> quarantine -> work order and diagnostics -> repair operations -> quality review -> condition and resale classification -> valuation -> inventory posting outbox -> authoritative inventory confirmation.

## Asset identity and quarantine
Each recovery asset is linked to its originating return item, order and person. Serial/IMEI mismatches block normal intake and require loss-prevention review. Returned assets remain quarantined until authorized workflow steps are complete.

## Refurbishment
Work orders capture diagnosis, repair operations, labor and parts. Battery replacement, screen replacement, ports, cameras, software restore, cleaning and data wipe are tracked separately. Per-asset cost ledger records handling, labor and replacement components.

## Quality and classification
- Open-box: grade A or B.
- Refurbished: grade A, B or C.
- Parts-only: grade C or D.
- Non-resellable: non-resellable grade only.

Serial mismatch, activation lock or failed inspection blocks resale classification. Data-wipe verification must be required by the device-specific quality checklist before resale.

## Cost and recovery value
Track asset-specific recovery costs; valuation stores recovered cost, estimated resale value and estimated net recovery. Costs are not equally allocated across devices. Currency conversion and landed-cost policy belong in the finance/pricing adapter; the initial posting function uses USD pending currency-aware integration.

## Inventory handoff
An idempotent outbox record is created for the authoritative inventory service. This module does not directly increment stock or create catalog listings. The inventory adapter must confirm a transaction reference before the asset is marked posted.

## Security and audit
RLS is enabled on all tables; service-role access only. RPCs are revoked from anon/authenticated. Audit history is append-only. Employee permissions, segregation of duties, quality-review authorization and location access must be enforced by the trusted API/role service before RPC calls.

## Dependencies
Build 009.53 RMA/inspection and refund workflow; Build 017 return inspection standards; authoritative inventory/warehouse, catalog, finance and pricing services.

## Validation
Run `npm run lint` and `npm run test:build009:inventory-recovery`. PostgreSQL integration tests must cover quarantine, serial mismatch, work-order lifecycle, operation cost totals, classification restrictions, activation-lock and data-wipe gates, valuation calculations, duplicate posting and outbox reconciliation.

## Rollout boundary
Implementation branch only. No live inventory posting, device diagnostics, employee workbench, parts procurement, market-price lookup, production valuation policy or catalog listing is claimed.
