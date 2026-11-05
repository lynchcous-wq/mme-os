# Build 008 — Public Catalog Consumer Compatibility Crosswalk

**Design branch:** `build-008-inventory-foundation`  
**Evidence branch:** `integration/build001-catalog-inventory`  
**Reviewed at evidence tree:** `05fa7bc9236a24d59104bc5df898bab2783937e0`  
**Review type:** Static source and migration inspection. No route, schema, or production data changed.

## 1. Executive decision

Do not remove `location_id` or `unit_id` from the current catalog responses in a one-step edit. The storefront uses these values as opaque checkout/cart references, not merely display metadata. However, the UI also exposes a shortened serialized unit database ID to customers, and the API returns a media storage key that the UI does not consume. The safe path is to preserve required opaque references behind a documented public contract while removing unused/internal fields and changing the serialized-unit presentation so customers do not see database IDs.

This is a compatibility crosswalk, not approval to expose these identifiers indefinitely. The checkout validator must independently revalidate all references and availability; it already does so server-side, but the public endpoints should still minimize their output.

## 2. Confirmed storefront consumers

| Consumer | Endpoint / data | Fields actually consumed | Compatibility impact |
|---|---|---|---|
| `components/home-live-products.tsx` | `GET /api/catalog` | `id`, `title`, `brand`, `category`, `catalog_condition`, `price_cents`, `currency`, `available_quantity` | Location-level availability objects and their internal identifiers are not consumed by the home live-products component. |
| `app/products/[id]/page.tsx` | `GET /api/catalog/:id` | Product identity/details, price/currency, total availability, specifications, warranty, media `id/media_type/external_url/alt_text/is_primary`; availability `location_id/location_name/available_quantity` | `location_id` is used as the selected pickup location, React key, cart field, and checkout reference. `location_code` is not used. Media `storage_key` is typed but not rendered. |
| `app/products/[id]/page.tsx` | `GET /api/catalog/:id/units` | `unit_id`, `location_id`, `location_name`, `condition_grade` | Unit ID becomes selected unit/cart `serialized_unit_id`; location ID and name become cart fulfillment references. UI currently displays the first eight characters of `unit_id` to customers. |
| `components/cart-provider.tsx` | Local cart state | `product_id`, `location_id`, `quantity`, `title`, `sku`, `price_cents`, `currency`, `location_name`, `available_quantity`, optional `serialized_unit_id` | Cart stores internal location/unit UUIDs locally. These are untrusted client references and must never authorize a purchase on their own. |
| `app/api/cart/validate/route.ts` | Checkout/cart validation | Accepts product/location IDs, optional serialized unit ID; verifies active product, published catalog product, active location, aggregate balance or exact serialized unit status/product/location | This is the server-side compatibility gate. It must remain authoritative and be tested against stale, forged, moved, sold, quarantined, and already-reserved references. |

The current `app/products/page.tsx` is a placeholder and does not fetch the catalog API. The homepage contains static sample merchandising data in `app/page.tsx`; the live inventory component is a separate component in the evidence tree. Confirm whether it is mounted in the active deployed homepage before treating it as a production storefront path.

## 3. Field-by-field disposition

| Response field | Current consumer need | Recommendation |
|---|---|---|
| Product `id` | Product detail route and cart | Retain as opaque public product identifier; validate server-side. |
| `location_id` | Product detail selection, cart and cart validation | Retain temporarily as opaque checkout reference. Do not display it. Longer-term replace with a signed/opaque location token or public location key if API threat review requires it. |
| `location_code` | No consumer found in inspected storefront | Remove from public response after contract test confirms no other caller. |
| `location_name` | Customer pickup/store display and cart display | Retain only if approved customer-facing display label; avoid exposing internal-only location names. |
| `unit_id` | Exact serialized unit selection and checkout validation | Retain only as an opaque reference in API/cart state; stop rendering any substring of the UUID to customers. Consider short-lived opaque token as a later hardening step. |
| `condition_grade` | Customer selection label | Retain if grade is approved customer-facing condition language; map internal grades to curated public labels rather than exposing internal enum names. |
| `storage_key` | No consumer; UI renders `external_url` only | Remove from public detail response. Keep private storage identifiers server-side. |
| `external_url` | Product image rendering | Retain only when URL is approved for public delivery and is not a private evidence/storage URL. |
| `location_code` and raw storage metadata | No consumer found | Remove from allowlist. |
| Serial number / IMEI | No storefront consumer | Never include in public catalog or unit availability responses. |

## 4. Stock eligibility crosswalk

### Aggregate inventory

The storefront list/detail and cart validation use `on_hand_quantity - reserved_quantity`, clamped to zero. The reservation lifecycle migration updates `reserved_quantity` transactionally when releasing an active order reservation and uses row-level updates/invariant checks. The catalog route's aggregate calculation is therefore only as complete as the balance ledger's reservation discipline. Preserve the database as source of truth; do not reproduce stock mutations in routes.

### Serialized inventory

The serialized-unit schema permits `in_stock`, `reserved`, `sold`, `repair`, and `quarantine`. The catalog units route selects `in_stock`, which excludes the other four states. The inspection migration separately models serialized-unit inspection/disposition and the inspection hold lifecycle. Before centralizing availability, verify the exact resolver transitions that move units into and out of `in_stock`; do not assume a pending inspection is sellable.

The serialized migration explicitly says serialized checkout remains disabled until dedicated order reservation/payment-consumption RPCs are reviewed and tested. The inspected cart validator accepts a serialized unit ID and checks that it currently belongs to the selected product/location and is `in_stock`, but a validation read is not a reservation. Do not represent the device as reserved or enable serialized checkout based solely on this validation endpoint.

## 5. Safe implementation sequence

1. Add route contract tests against the exact response fields above before changing any response shape.
2. Add negative security assertions: no serial/IMEI, supplier or landed cost, private evidence path, storage key, employee/person identity, or raw inspection details.
3. Remove unused `location_code` and `storage_key` only after tests prove no supported consumer requires them.
4. Change the unit selector so it displays a curated public label (store + public condition + non-identifying sequence label if required), never a UUID substring.
5. Keep internal IDs as untrusted references only; cart validation must re-check active/published product, active location, exact unit ownership/state, price, and available stock at checkout.
6. Centralize list/detail/unit availability only after a database-level eligibility query or projection has been identified and proven equivalent for aggregate reservations, channel claims, inspection/disposition, and serialized status.
7. Add concurrency tests for simultaneous cart validation/checkout and exact serialized-unit reservation. A read-only availability endpoint cannot guarantee inventory remains available.
8. Keep Build 004 authorization gates for employee inventory operations; this public catalog work does not authorize privileged inventory route changes. Keep Build 007 CRM dependencies out of this public response contract.

## 6. Remaining verification gates

- Confirm `HomeLiveProducts` is actually mounted in the active homepage entrypoint; current homepage source also contains static sample cards.
- Verify all route callers beyond the inspected storefront and cart validator before removing any fields.
- Inspect the complete serialized disposition resolver and any inspection state that could leave a unit `in_stock` while a pending inspection exists.
- Verify channel-claim accounting is reflected exactly once in aggregate `reserved_quantity`.
- Add live database-backed route tests; static consumer tracing is not runtime validation.
- No production deployment, API contract cutover, or serialized checkout enablement is authorized by this document.

## 7. Conclusion

The compatibility-sensitive identifiers are `location_id` and `unit_id`, because the existing cart and checkout validation contract depends on them. Their use can be retained as opaque, non-authorizing references while the customer-facing unit UUID display and unused internal response fields are removed. The next safe code step is to add the catalog route contract/security tests and lock this response contract before modifying the handlers.
