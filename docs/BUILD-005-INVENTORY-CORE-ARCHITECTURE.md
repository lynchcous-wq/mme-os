# Build 005 — Inventory Core Architecture

**Stage:** 005.1 — Architecture and data ownership  
**Status:** Architecture specification; not a database migration or deployed feature  
**Repository:** `lynchcous-wq/mme-os`  
**Branch:** `implementation/build-005-inventory-core`  
**Depends on:** Build 001 inventory/order foundation; Build 004 identity and authorization foundation

## 1. Purpose and guardrails

Define a reliable inventory model for new, used, refurbished, open-box, damaged, and parts-only electronics across MME locations and sales channels.

This document is additive. Before any schema migration is written, inspect the current Build 001 schema and application code, map existing entities and constraints, and identify exact extension points. Do not create a second product, order, location, or stock ledger when an equivalent source-of-truth already exists. Do not rename, drop, truncate, or repurpose existing production objects. No production migration or deployment is authorized by this specification.

Build 004 remains the intended identity and authorization foundation. Inventory access must be enforced by trusted server-side services and scoped permissions; UI visibility, profile colors, job titles, and client-supplied metadata are not authorization.

## 2. Inventory identity model

Keep these concepts distinct:

1. **Product family / catalog product** — The customer-facing model or product listing, such as a particular television model. Holds brand, manufacturer, model, category, descriptive content, specifications, images, and supported demo media.
2. **Sellable SKU / offer** — The MME-defined sellable configuration and merchandising identity. A product can have separate SKUs for materially different configurations, bundles, or conditions where pricing and fulfillment differ. SKU is unique within the MME business namespace and is never derived solely from a mutable title.
3. **Inventory unit** — A physical, individually countable item. It may carry a serial number, IMEI, condition assessment, acquisition record, cost basis, location, and lifecycle status. Serialized devices are tracked one unit at a time. Non-serialized accessories may be tracked as quantity lots or stock balances, subject to the same movement ledger.
4. **Inventory lot / receipt line** — A traceable acquisition grouping from a purchase, pallet, vendor shipment, or receiving event. It preserves supplier and source-document references and supports item-specific landed cost.
5. **Offer / channel listing** — A channel-specific representation of an available SKU and price. Website, in-store POS, auction, and other channels must reference the same inventory authority rather than maintain independent quantities.

A title or model number is not a SKU. A SKU is not a serial number. An IMEI or serial number identifies a physical unit and must not be used as the customer-facing SKU.

## 3. Core domain records

The logical model should map to existing Build 001 objects wherever possible. Names below are conceptual and are not instructions to create duplicate tables.

- Catalog product and product specifications.
- SKU and SKU-to-product relationship.
- Inventory unit for serialized stock.
- Inventory lot / receiving batch and receipt line.
- Inventory location and location type.
- Stock movement ledger.
- Inventory reservation / allocation.
- Condition assessment and inspection evidence.
- Cost layer / landed-cost allocation.
- Channel availability projection.
- Audit event and actor reference.

Every record needs stable identifiers, created/updated timestamps where mutable, and explicit lifecycle state. Use foreign keys and database constraints for referential integrity. Store money as integer minor units or fixed-precision decimal with an explicit currency; never use floating-point for monetary values.

## 4. Serial number and IMEI rules

- Support multiple identifiers per physical unit, each with an identifier type and issuer/context where applicable.
- Normalize identifiers for matching while preserving the original captured value for display and evidence.
- Enforce uniqueness for active identifiers within the appropriate identifier namespace; account for manufacturer reuse and identifier type rather than assuming every serial namespace is globally unique.
- IMEI validation should include format/check-digit validation where applicable, but a valid format does not prove ownership, activation status, blacklist status, or device authenticity.
- Restrict full IMEI and other sensitive device identifiers to authorized roles and mask them in ordinary lists, receipts, logs, and customer-facing pages.
- Never expose full device identifiers in public website payloads, analytics events, or URLs.
- Record who captured or changed an identifier, when, and why; changes require privileged, audited workflows.

## 5. Condition and inspection

Support controlled condition grades including new, refurbished, used, open-box, damaged, and parts-only. Keep grade separate from the inspection facts supporting it.

Inspection evidence should be extensible for:
- Power-on and functional tests.
- Screen, battery, ports, cameras, speakers, connectivity, and included accessories where relevant.
- Activation / account lock checks where legally and operationally appropriate.
- Photos, defect notes, missing components, and inspector identity.
- Test date, test procedure/version, and pass/fail/not-tested state.

A condition change must be an audited event. Do not infer that a device is refurbished merely because it has been tested, or that a device is new because no prior sale is found.

## 6. Locations, states, and stock movement

Support store floor, display, restricted stockroom, warehouse, in-transit, receiving/inspection, quarantine/hold, customer pickup staging, and other configured locations. Location names and capabilities are configuration, not hard-coded permissions.

Use an append-only stock movement ledger as the source of truth for quantity changes. A movement records item/SKU or lot, quantity, source and destination, reason, actor, timestamp, reference document/order, and idempotency key. Correct mistakes with compensating movements; do not silently edit or delete posted movements.

Suggested unit lifecycle: expected, received, inspection_pending, available, reserved, display, quarantined, sold, fulfilled, returned_pending_inspection, returned_available, returned_quarantined, transferred, lost, damaged, and disposed. The exact transition graph must be approved and enforced server-side. Avoid treating every status as a physical location.

## 7. Reservations and channel availability

- Reservations must be atomic and concurrency-safe so two channels cannot sell the same unit.
- Reservation records require source order/cart, quantity or unit IDs, expiration, status, and idempotency key.
- Expired or cancelled reservations release stock through a controlled transition.
- Available-to-sell is a derived projection from posted stock, holds, reservations, and channel rules; it is not an independently editable count.
- Website shipping and local pickup, in-store POS, and auction workflows must call the same inventory reservation/commit services.
- A website "coming soon" listing is a merchandising state and must not imply sellable stock or allow checkout before receiving/availability rules are met.
- Channel caches and search indexes are projections only; they must reconcile to the inventory authority.

## 8. Costing and pricing separation

Keep acquisition cost, landed cost, retail/list price, sale price, and margin as distinct values.

- Preserve source purchase price at receipt or lot level.
- Allocate freight, taxes, auction fees, handling, and other approved costs using an explicit allocation method.
- Support variable item-level landed cost; do not divide a pallet's total cost equally across unrelated items by default.
- Record allocation inputs, method, actor, timestamp, and source document so calculations can be reproduced.
- Price changes and markdowns are separate from cost changes and must retain price history and approval evidence where required.
- Gross margin calculations must use the relevant recognized cost basis and exclude tax from revenue where applicable.
- Currency and rounding rules must be explicit.

## 9. Barcode and product data

Barcode labels should resolve to a stable MME SKU or inventory-unit identifier, not encode sensitive IMEI/serial values in plain text. The existing user preference remains: 2 × 3 inch label, optional uploaded MME logo, QR disabled by default, automatic information density. The label format is configurable and must not alter underlying identity rules.

Product data should support category-specific specifications (for example TV resolution/refresh rate, laptop processor/RAM/storage, and phone model/storage/network compatibility), searchable descriptions, images, and demo-video references. Treat vendor-supplied descriptions and external content as untrusted input and sanitize before rendering.

## 10. Integrations and event boundaries

Inventory is the authority for stock availability. Orders, POS, website, auction, returns, shipping, local pickup, analytics, and demo portal consume controlled APIs/events and must not independently write stock balances.

Use transactional outbox or an equivalent reliable event-delivery pattern for downstream website and channel updates. Events need stable IDs, schema versions, timestamps, and idempotent consumers. Failed delivery must be retryable and observable without duplicating stock movements or orders.

## 11. Security, privacy, and audit

- Deny by default; enforce resource, action, and location scope on the server.
- Separate catalog-edit, receiving, inspection, stock-adjustment, transfer, pricing, cost-view, and inventory-admin permissions.
- Restrict cost and full device identifiers to approved roles.
- Require reason codes and audit evidence for adjustments, overrides, write-offs, identifier edits, and privileged condition changes.
- Do not trust client-supplied price, cost, availability, role, actor, or location scope.
- Never place Supabase service/secret keys in browser code, public environment variables, logs, or source control.
- Audit records should be append-only for application runtime roles; this is not a claim of tamper-proof storage against database owners.

## 12. Reconciliation and reporting

Provide reconciliation views for:
- Ledger-derived on-hand quantity versus location/SKU projections.
- Serialized unit count versus serialized stock balances.
- Available-to-sell versus reservations and holds.
- Website/POS/auction channel projections versus the inventory authority.
- Receipt totals and allocated landed costs versus source purchase documents.
- Negative stock, duplicate identifiers, orphaned units, and stale reservations.

Every discrepancy should produce an actionable exception with source references and resolution history. Reports must distinguish live verified values from projections and cached data.

## 13. Implementation gates

Before writing migrations or application code:

1. Inspect Build 001 schema, migrations, models, order tables, location tables, and existing stock movement logic.
2. Produce an entity crosswalk: existing object, intended responsibility, reuse/extend decision, migration impact, and owner.
3. Identify all existing uniqueness, foreign-key, RLS, grant, and trigger behavior.
4. Confirm Build 004 server authorization integration and avoid bypassing its closed table boundary.
5. Design additive migrations with preflight checks, rollback/recovery notes, and development-only application.
6. Add tests for duplicate SKU/identifier rejection, concurrent reservations, movement idempotency, compensating adjustments, independent channel projections, variable landed-cost allocation, and role/location access boundaries.
7. Run repository build, type checks, tests, and dependency audit in the approved development workflow. Record actual output; do not claim tests passed without execution.

## 14. Out of scope for this architecture stage

No SQL migration, database mutation, UI, barcode output, live website sync, POS/auction connection, pricing engine, or production deployment is performed by this document. Those follow only after the Build 001 crosswalk and architecture review.
