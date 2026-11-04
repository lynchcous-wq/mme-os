# Build 001 — Barcode & Scanner Intelligence

**Status:** Proposed additive migration; not applied.

## Barcode label defaults
Retains the existing versioned 2×3-inch label profile: MME logo on, QR off, automatic information density. Print items can now bind to a specific serialized unit and retain serial/IMEI snapshots. Existing print rendering remains a trusted print-service responsibility.

## Scanner resolution
A trusted scanner endpoint resolves MME SKU/barcode payloads, serial numbers and IMEIs. It returns catalog and unit context while recording an audit event. Unknown and ambiguous scans are explicit outcomes; IMEI values are never returned in full (only last four digits).

## Physical cycle counts
Employees with authorized location access can open a count for all items, selected products, serialized-only items or aggregate-only items. Expected quantities are snapshotted into count lines. Aggregate scans increment counted quantity; serialized scans count the specific physical unit once. Counts submit to review; this migration intentionally does not post variances automatically.

## Required service layer
The trusted server must authenticate the employee, verify role and location access, rate-limit scans, validate device references and authorize count opening/submission. It must prevent duplicate rapid scans for aggregate products where scanner hardware emits repeated events; use an operator confirmation or a configurable debounce window. CEO/manager approval and the final adjustment-posting workflow will be added separately. No browser service-role key is permitted.

## Operational boundary
The schema records scanner events and count sessions but does not itself pair scanners, print labels, render barcode images, send data to a printer, or post count adjustments. Hardware integrations and a reviewed count-variance posting RPC remain required.