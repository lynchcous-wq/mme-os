# Build 001 — serialized device inventory

**Status:** Proposed additive migration. Not applied to a database. Serialized online checkout remains disabled.

## Device-level ledger
- One row per physical serialized unit, linked to an active serialized catalog product and store location.
- Unique serial number and unique non-null IMEI prevent duplicate intake.
- Tracks condition independently per unit: new, open box, refurbished, used.
- Tracks unit state: in stock, reserved, sold, repair, quarantine.
- A separate reservation history table captures serial/IMEI snapshots and permits only one active reservation per physical unit.

## Intake
The service-role-only `mme_receive_serialized_unit` function validates the product is active and marked serialized, validates the store location and identifiers, and records the device. Duplicate serials/IMEIs are rejected by database constraints.

## Checkout boundary
The existing aggregate-quantity checkout RPC intentionally rejects serialized products. This migration does not change that behavior. Before enabling serialized checkout, add and test an atomic serialized-order path that locks selected unit IDs, snapshots identifiers on order lines, reserves exactly one physical unit per line, releases it on payment failure/expiry, and marks it sold only after a verified Stripe success event. IMEI/serial values must never be exposed in public catalog responses.

## Required tests
Run against a disposable PostgreSQL/Supabase database: duplicate serial rejection, duplicate IMEI rejection, cross-location intake, inactive/non-serialized product rejection, state transition permissions, and concurrent attempts to reserve the same unit once serialized checkout is implemented.
