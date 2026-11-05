# Build 008 — Public Catalog Route Contract Findings

**Evidence branch:** `integration/build001-catalog-inventory`  
**Reviewed files:** `app/api/catalog/route.ts`, `app/api/catalog/[id]/route.ts`, `app/api/catalog/[id]/units/route.ts`  
**Review type:** Static source inspection. No runtime code, schema, or production data changed.

## 1. Executive finding

The three public handlers already return hand-built JSON objects rather than serializing complete database rows. This is a useful starting allowlist, but the current response contracts still disclose internal identifiers and operational metadata. The unit endpoint exposes opaque serialized-unit IDs and internal location IDs. The list/detail endpoints expose location IDs and operational location codes. Product detail also exposes media storage keys. These fields should be reviewed against actual storefront consumers before being removed or replaced.

The three handlers independently calculate availability and use service-role REST reads. Their calculations are similar but not centralized, so drift and stock-model inconsistencies remain possible.

## 2. Route-by-route findings

### A. `GET /api/catalog`

**Positive controls observed**
- Explicit table column selections rather than `select=*`.
- Only active commerce products linked to a catalog product are selected.
- Only published catalog products and active store locations are selected.
- The response is assembled field-by-field.
- Errors return a generic message rather than raw database response content.
- Aggregate and serialized branches are selected using the commerce product's persisted `serialized` flag; they are not added together.

**Issues to resolve**
1. The public availability objects include `location_id`, `location_code` and `location_name`. Internal UUIDs and operational codes should not be exposed unless a documented storefront contract requires them.
2. Serialized availability counts units in `in_stock` by product and location. The query does not explicitly join the catalog publication state at the unit query, though the final product is filtered through the active/published product join. Confirm the stock eligibility rules (quarantine, inspection, damage, pending disposition, reservations) and enforce them in one canonical source.
3. Aggregate availability uses `on_hand_quantity - reserved_quantity`. Confirm that every active reservation and channel claim is reflected in this canonical reserved quantity, exactly once.
4. The endpoint returns `serialized`, `catalog_condition`, and raw `specifications`. Confirm these are intentionally public and sanitize specification values before rendering.
5. If any of the six parallel reads fails, the whole list returns 502. This is fail-closed for availability but removes the whole catalog; decide whether that is the intended storefront behavior.

### B. `GET /api/catalog/[id]`

**Positive controls observed**
- Validates UUID syntax and requires an active commerce product linked to a published catalog product.
- Selects named columns, not whole rows.
- Uses separate aggregate and serialized availability branches.
- Returns a generic 502 message on data-source failure.

**Issues to resolve**
1. Availability exposes `location_id` and `location_code`, as does the list route.
2. Media response includes `storage_key`. A storage key is an internal storage implementation detail; return a public, access-controlled media URL or public media identifier only where required.
3. The media query retrieves all product media and filters in application code. Prefer filtering by the catalog product ID in the database query to minimize service-role data retrieval.
4. The detail query selects `upc_ean`, `model_number`, `manufacturer`, and `tracking_mode`. These may be legitimate product attributes, but their public status should be explicit in the field contract.
5. Detail and list implement separate availability logic. A shared, tested stock availability contract should keep their quantities and location presentation consistent.
6. The route treats a missing catalog record as 404, which is appropriate, but availability-source failures should remain distinguishable internally without exposing database details to clients.

### C. `GET /api/catalog/[id]/units`

**Positive controls observed**
- Validates product UUID.
- Confirms the product exists, is active, and is marked serialized.
- Restricts returned units to `unit_status= in_stock`.
- Uses a hand-built response rather than returning database rows.

**High-priority disclosure**
- The response returns `unit_id` and `location_id` for every available serialized unit. These opaque identifiers expose internal inventory records and are not needed for a normal public availability display.
- The route also reveals per-unit condition grade and precise location name. Confirm whether per-unit grade/location detail is a required storefront feature; if not, aggregate counts by approved public condition/location label.
- The units query does not select serial number or IMEI, which is good; keep those fields out of all public responses.

**Recommendation**
Replace the per-unit response with a minimal availability summary grouped by approved public labels, or deprecate the route after checking callers. Do not silently change a contract until storefront consumers are identified.

## 3. Cross-route consistency and security findings

| Finding | Severity | Evidence | Required action |
|---|---|---|---|
| Public unit IDs and internal location IDs exposed | High | Units route response contains `unit_id`, `location_id`; list/detail contain location IDs | Consumer inventory and version a minimized response contract |
| Internal storage key exposed | Medium | Detail media maps `storage_key` to response | Replace with approved public media URL/identifier |
| Three independent availability implementations | High | Each handler calculates availability separately | Centralize or use one canonical server-side projection |
| Reservation/claim deduction semantics not proven at route level | High | Aggregate path subtracts `reserved_quantity`; no end-to-end test verifies all claim owners | Add database-backed concurrency and reconciliation tests |
| Serialized eligibility semantics incomplete in route query | Medium | Counts only `in_stock` units | Verify canonical eligibility and inspection/disposition gates |
| Service-role reads in public handlers | Medium / expected architecture | Each route uses server-side service key | Retain server-only key; strictly minimize selected and returned fields |
| No catalog route tests in inspected `tests/` directory | High | Only three workflow API contract tests were present in the inspected tree | Add route-level contract/security tests and register in CI |

## 4. Proposed public response contract

Keep current product identifiers and customer-facing product attributes where the storefront needs them, but define an explicit schema. Suggested safe availability shape:

```ts
type PublicAvailability = {
  location_label?: string; // approved public label only
  condition_grade?: string; // only if product requirement needs it
  available_quantity: number;
};

type PublicProduct = {
  id: string;
  sku?: string; // retain only if public SKU is intended
  title: string;
  description: string | null;
  brand: string | null;
  category: string;
  condition: string;
  specifications: Record<string, unknown>;
  warranty_summary: string | null;
  price_cents: number;
  currency: string;
  availability: PublicAvailability[];
  available_quantity: number;
};
```

Never include:
- serial number or IMEI;
- serialized-unit database ID;
- internal location UUID or location code;
- supplier, acquisition or landed cost;
- employee/person identity;
- inspection notes, private evidence path or security case detail;
- raw media storage key.

If customers need location-specific pickup options, expose a deliberately public location slug/label, not the internal location primary key.

## 5. Compatibility and implementation guardrails

Before implementation:
1. Search the repository for all consumers of `/api/catalog`, `/api/catalog/[id]` and `/api/catalog/[id]/units`.
2. Identify whether any customer-facing screen requires unit-specific condition or store-level availability.
3. Define a versioned response schema and migration path for consumers.
4. Inspect the actual stock model and reservation/claim SQL; do not infer it from UI behavior.
5. Build route tests with synthetic canary values for unit ID, location ID, serial, IMEI, cost, supplier, employee, inspection note and storage key.
6. Assert the canary values never appear in success, error or unavailable responses.
7. Test that list and detail return consistent availability for the same product and stock snapshot.
8. Test aggregate and serialized products separately, including claims/reservations and unknown stock-model states.

## 6. Implementation decision

**Do not edit these three route files yet.** The current response fields may be consumed by storefront code, and the repository inspection has not yet identified all consumers or established a shared canonical availability projection. Removing fields now could break the website, while retaining them without tests leaves unnecessary exposure.

The next safe step is a repository-wide consumer and schema crosswalk, followed by failing response-contract tests. Only then should the smallest compatible route change be made.

**Scope note:** This review does not complete Build 004 identity authorization, does not implement Build 007 CRM, and does not authorize production cutover.
