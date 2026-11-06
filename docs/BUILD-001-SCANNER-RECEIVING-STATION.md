# Build 001 — Scanner & Receiving Station

**Status:** Proposed additive migration; not applied.

## Scanner support
The station accepts product SKU, MME-prefixed Code 128 payload, serial number and IMEI. It resolves catalog items server-side and returns a limited product summary. Unknown scans are logged for exception handling. Aggregate products can be scanned with a quantity; serialized products require one-by-one serial/IMEI intake and cannot be received as bulk quantities.

## Receiving workflow
Open a session against a store location and optionally a purchase order. Every scan records the operator, scan type, value, result and sequence. Submit the session after scanning. PO-linked aggregate receipt completion groups matching scans by PO line and invokes the existing partial-receiving transaction, preserving PO quantity caps and inventory movement records. A serialized SKU scan must be completed with its individual serial number, optional IMEI and condition before it is treated as received.

## Device support
Scanner input can originate from USB keyboard-wedge, Bluetooth HID or a network-connected station; these transport modes are client/agent integrations, not enabled by the database migration. The UI should support camera scanning only where browser permissions and a compatible device are available.

## Controls and limitations
The tables and RPCs are service-role only. The trusted server must verify actor identity, role and location access. IMEI and serial values are sensitive inventory identifiers: restrict display, encrypt backups and avoid logging full IMEI in application telemetry. This migration does not implement the physical scanner driver, UI, network transport, or device provisioning. PO-less receipts and serialized PO line reconciliation require a subsequent extension; current completion is PO-linked aggregate receiving, while serialized unit intake is staged individually through its dedicated RPC.
