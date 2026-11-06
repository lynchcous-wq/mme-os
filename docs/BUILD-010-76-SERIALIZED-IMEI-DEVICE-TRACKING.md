# Build 010.76 — Serialized Electronics & IMEI Tracking

## Implemented
- Individual device registry tied to catalog item and physical location.
- Serial number, IMEI 1 and IMEI 2 fields with unique indexes and cross-slot collision checks.
- IMEI 14–16 digit and Luhn checksum validation.
- Condition grade, acquisition reference/date, optional cost basis, warranty reference and generated MME barcode identifier.
- Device lifecycle event history with actor, status transitions, source reference and timestamps.
- Controlled blacklist, unblacklist, missing, recovery, repair, return and retirement transitions.
- Fulfillment device manifest binds individual devices to fulfillment lines and prevents duplicate device assignment.
- Serialized fulfillment posting validates manifest quantity, SKU and location, then marks device assets sold and posts inventory movement in the same database transaction.
- Authenticated inventory API and device registry dashboard.
- RLS and service-role-only direct table access.

## Important release boundaries
- MME blacklist status is an internal flag only. No carrier, OEM, GSMA or law-enforcement blacklist lookup is performed.
- No barcode image/PDF generation or scanner hardware integration is configured; the registry creates a stable barcode value for downstream printing/scanning.
- Device registration does not increment stock balances automatically. Opening balances must be established through a verified inventory count; serialized device counts need a unit-level reconciliation workflow before live opening stock.
- Fulfillment line device manifest scanning is an authenticated operation; actual hardware scanner integration remains separate.
- This build adds a serialized posting RPC. Confirm the warehouse worker/API calls this RPC for serialized lines before enabling shipping. The older quantity-only posting RPC intentionally continues to reject serial/IMEI-tracked items.
- Warranty-provider integrations, carrier verification, device financing/activation and external stolen-device services are not connected.

## Validation
Run `npm run test:build010:serialized-imei-device-tracking`, inventory, fulfillment, POS, returns and warranty suites, `npm run lint`, and `npm run build`. Tests not executed; migration not applied; not merged or deployed.
