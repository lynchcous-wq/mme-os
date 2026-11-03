# Build 001 — Barcode Label Engine

**Status:** Proposed additive migration; not applied.

## Default label profile
2 × 3 inch stock, MME logo enabled, QR disabled, automatic information density, Code 128 barcode. Profile fields allow the logo, product title, SKU, condition, price, serial suffix and location to be selected. Width and height remain fixed to the approved 2×3 stock in this phase.

## Versioning and print batches
Every profile change creates a configuration snapshot with a monotonically increasing version. Print jobs retain the profile version and product title/SKU/condition/price snapshots so reprints can reproduce the original data. Jobs record printer name, connection type, status and failure details.

## Barcode and serial handling
The initial barcode payload is `MME:` plus the product SKU and uses Code 128. It identifies the product, not an individual serialized unit. The optional serial suffix is only the final four alphanumeric characters supplied by the trusted service; full IMEI/serial values are not printed or stored by this label module. A future serialized-item label integration must bind to the authoritative serialized inventory record and use a unique per-unit barcode.

## Rendering boundary
This database migration creates print jobs and immutable snapshots. A trusted server/desktop print agent must render barcode graphics and the uploaded MME logo, fit text using the automatic density rules, and send output to supported USB/network/Bluetooth/system printers. Actual printer output, calibration and label-feed alignment are not implemented or verified by this commit.

## Security
All tables and RPCs are service-role only. The application must authenticate the employee, authorize label-profile edits, protect the MME logo in private storage, validate image type/size, and use the verified actor identity. Service-role credentials must never reach the browser. Logo paths are restricted to the MME branding namespace.
