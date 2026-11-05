# Build 008 — P0 Catalog Route Test Integration Gate

**Build 008 branch:** `build-008-inventory-foundation`  
**Catalog implementation evidence branch:** `integration/build001-catalog-inventory`  
**Reviewed Build 008 HEAD:** `3f41205cede41a7f579ab3f6001cf8b828294149`  
**Review type:** Repository tree and source-presence verification. No application code or production data changed.

## 1. Finding: test target is not present on the Build 008 branch

The Build 008 branch currently contains the project shell, package manifest, architecture documentation, and Build 008 planning documents. Its tracked tree does **not** contain:

- `app/api/catalog/route.ts`
- `app/api/catalog/[id]/route.ts`
- `app/api/catalog/[id]/units/route.ts`
- `app/products/[id]/page.tsx`
- `components/home-live-products.tsx`
- `components/cart-provider.tsx`
- `app/api/cart/validate/route.ts`
- a `tests/` directory or the Build 001 route test harness.

These implementation files were inspected on `integration/build001-catalog-inventory`. The two branches therefore do not currently share the same testable catalog implementation baseline.

## 2. Why tests are not being added to this branch yet

A route contract test must exercise the exact route implementation and its dependencies. Adding tests now to a branch that has neither the route handlers nor the existing test harness would create a false impression of executable coverage. Copying route code or a test harness into Build 008 without a reviewed branch integration would also create duplicate source-of-truth risk.

No tests are claimed as added or passing in this step.

## 3. Required integration sequence

1. Confirm the Build 001 catalog implementation branch/commit intended to become the canonical parent for Build 008.
2. Integrate the Build 001 catalog baseline into Build 008 through a reviewed Git operation (merge/rebase/cherry-pick as appropriate); do not overwrite the Build 008 architecture documents.
3. Re-run the existing CI baseline and verify that catalog, cart, reservation, serialized-unit, inspection, and migration tests remain intact.
4. Add the following Build 008 route tests against the integrated source:
   - `tests/build008-public-catalog-list.security.test.mjs`
   - `tests/build008-public-catalog-detail.security.test.mjs`
   - `tests/build008-public-unit-availability.security.test.mjs`
   - `tests/build008-stock-model-availability.contract.test.mjs`
5. Register the suites in `package.json` and CI only after the tests run locally/against the repository's established harness.
6. Only then make response-shape changes, with compatibility assertions for product detail, pickup location selection, serialized unit selection, and checkout validation.

## 4. Test assertions to preserve

### Public catalog list
- Response is an allowlisted product projection, not a raw database row.
- No serial/IMEI, supplier/cost, employee/person identity, inspection evidence, or internal storage key.
- Product ID, title, condition, price/currency, and public availability remain compatible with the homepage consumer.

### Public catalog detail
- Product details, specifications, warranty, public media URL/alt text, and availability remain compatible with the product detail page.
- Remove unused `location_code` and media `storage_key` only after asserting no supported caller depends on them.
- Pickup selection retains a valid opaque location reference until the cart contract is migrated.

### Serialized-unit availability
- Only eligible units are returned; never return serial number or IMEI.
- Unit reference remains opaque and usable for checkout validation, but is never rendered in customer-facing text.
- Return only approved public location and condition labels.
- A pending inspection, active reservation, quarantine, repair, sold state, or other non-sellable state must not appear as available.

### Stock model contract
- Aggregate and serialized inventory remain mutually exclusive according to the persisted product tracking mode.
- Aggregate availability accounts for reservations and any applicable channel claims exactly once.
- Serialized availability is based on the canonical sellable-unit eligibility rule, not aggregate balances.
- Read-time availability is informational; only an atomic reservation/checkout transaction can claim stock.

## 5. Authorization and release boundaries

- This work is public catalog contract hardening, not permission to change privileged employee inventory routes.
- Build 004 identity authorization remains a prerequisite for protected employee inventory operations.
- Build 007 CRM integration is not introduced into public catalog responses.
- Serialized checkout remains disabled until dedicated serialized reservation and payment-consumption RPCs are reviewed and tested.
- No merge, production deployment, live payment, or production authorization cutover is authorized by this document.

## 6. Exit criteria

This gate is cleared only when Build 008 contains the canonical Build 001 catalog source, its dependency/test harness, and a passing CI run on the integrated branch. Until then, route-test implementation is intentionally blocked to avoid unexecutable or duplicate tests.
