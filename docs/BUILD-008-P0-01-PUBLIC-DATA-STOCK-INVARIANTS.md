# Build 008 — P0 Implementation Package: Public Inventory Data Minimization and Stock-Model Invariants

**Branch:** `build-008-inventory-foundation`  
**Package ID:** `B008-P0-01`  
**Status:** Ready for gated implementation planning; runtime changes are not yet authorized by dependency state  
**Scope:** Public catalog response safety and aggregate-versus-serialized stock integrity  
**Out of scope:** Employee inventory mutations, CRM-linked holds, payment/checkout changes, new inventory ledgers, production rollout.

## 1. Current dependency checkpoint

At review time, Build 004 PR #14 is still **open, draft and unmerged**, targeting `integration/build001-catalog-inventory`. Its latest observed head is `704205744b0f997df7adf7c8440a16fd0e4b45c0`. Build 008 remains on `build-008-inventory-foundation` at commit `58f9ec32968cc7b38bb8029b0dc262bc4e3b6690`.

Therefore:
- This package may be prepared and reviewed, but must not introduce privileged employee inventory routes or claim the Build 004 identity gate is complete.
- Do not rebase onto or merge Build 004 without approval.
- Build 007 CRM remains a separate implementation gate; this package deliberately excludes CRM customer-hold and quote conversion.
- The inspected Build 001 integration branch is the evidence baseline, not a statement that its code is deployed to production.

## 2. Package objective

Establish two P0 invariants without creating new inventory owners:

1. Public catalog endpoints return only explicitly allowlisted product content and safe, appropriately aggregated availability. No serial number, IMEI, opaque serialized-unit ID, internal location ID, cost, supplier, employee, inspection or evidence data may escape.
2. A product's stock model is explicit and its availability calculation cannot count the same physical stock through both aggregate balances and serialized units.

This is a hardening package over Build 001. It must preserve the current catalog and inventory schema ownership.

## 3. Exact candidate files

### Existing runtime files to inspect and, if necessary, modify

- `app/api/catalog/route.ts`
  - Replace broad/raw row composition with a typed public projection.
  - Explicitly select public product fields.
  - Compute availability through one approved stock-model-aware projection; never concatenate aggregate and serialized quantities.
  - Do not include raw serialized unit identifiers or precise internal location identifiers in public JSON.
  - Fail safely when availability cannot be computed; do not substitute stale or privileged stock details.

- `app/api/catalog/[id]/route.ts`
  - Apply the same response allowlist and safe availability contract to product detail.
  - Preserve active/published/version checks.
  - Ensure media, category and product-version fields are public-only.

- `app/api/catalog/[id]/units/route.ts`
  - Review whether this public endpoint is necessary. Preferred behavior is to return safe aggregate availability or a minimal non-identifying availability summary.
  - Do not return serial, IMEI, opaque unit IDs, internal location IDs, employee attribution, inspection notes or evidence paths.
  - If no product requirement exists for a unit-level public endpoint, deprecate it safely rather than disclosing internal unit references.

- `lib/server/<existing-catalog-or-inventory-query-module>`
  - Use the actual existing shared module if one is found during implementation. Do not create a second data-access abstraction merely to satisfy this plan.
  - Centralize the allowlisted projection and stock-model-aware availability calculation so list/detail endpoints cannot drift.

### Existing schema owner to inspect before any migration

- Existing product/catalog stock-model field(s), if present.
- `mme_inventory_balances` and existing availability views/functions.
- `mme_serialized_units` and product linkage.
- `mme_channel_stock_claims`, `mme_inventory_reservations` and their effects on sellable quantity.

**Migration rule:** No new table or migration is presumed. If a stock-model discriminator or safe availability projection is missing, first prove the gap against the complete schema and propose the smallest additive change to the existing owner. Any migration must have explicit rollback and pgTAP coverage.

## 4. Exact new/extended tests

Add route-level tests using the repository's existing test framework and conventions. Suggested file names, to be confirmed against the current test tree before creation:

- `tests/build008-public-catalog-list.security.test.mjs`
- `tests/build008-public-catalog-detail.security.test.mjs`
- `tests/build008-public-unit-availability.security.test.mjs`
- `tests/build008-stock-model-availability.contract.test.mjs`

Required seeded sensitive values:
- a recognizable fake serial number;
- a recognizable fake IMEI;
- a fake internal unit UUID;
- a fake internal location UUID;
- a fake supplier name/reference;
- a fake acquisition cost;
- a fake employee/person UUID;
- a fake inspection note and private evidence path.

For each public route, assert all sensitive values are absent from:
- success JSON;
- not-found and validation errors;
- unavailable/timeout responses;
- response metadata and debug fields;
- any test-captured log output.

Also assert that required public product data remains present and correctly shaped.

### Stock-model invariant tests

1. Aggregate-managed product: availability derives from aggregate on-hand less aggregate reservations/claims according to the existing canonical function.
2. Serialized-managed product: availability derives from eligible serialized units less active unit reservations/claims.
3. No double count: serialized units do not get added to an aggregate balance for the same stock pool.
4. Mixed or unknown stock model: reject or return unavailable; never silently sum both representations.
5. Inactive/unpublished product: no public availability.
6. Stale or unavailable stock source: return the documented fail-safe response, not an invented zero or stale positive quantity.
7. Claim/reservation changes: availability reflects the canonical reservation owner exactly once.
8. Location scoping: public response uses only approved public location labels or aggregate totals; internal location IDs are not emitted.

If the existing schema has no explicit stock model, the first task is a schema crosswalk and design review, not guessing a new enum or column.

## 5. Acceptance criteria

- [ ] All public catalog handlers use explicit public field allowlists.
- [ ] No serial/IMEI or opaque unit identifiers appear in any public response.
- [ ] No supplier, internal cost, employee, inspection or private evidence data appears in any public response.
- [ ] Public unit endpoint is either safely minimized or retired with a compatibility plan.
- [ ] Aggregate and serialized stock are never summed together for the same stock pool.
- [ ] Reservations and cross-channel claims are deducted exactly once.
- [ ] Unknown stock model and availability-source failures fail safely.
- [ ] List and detail availability agree for the same product/location/snapshot.
- [ ] Tests cover success, error, unavailable, and sensitive-data leakage paths.
- [ ] Existing catalog, checkout and inventory test suites remain green.
- [ ] Full CI, fresh migration chain and pgTAP pass on the implementation branch.
- [ ] No production secret, live inventory, or external provider is needed for tests.

## 6. Implementation sequence

1. Confirm current branch/base and retrieve exact source/test/package conventions.
2. Inspect complete catalog handlers, shared query helpers, schema, RLS/grants and availability SQL.
3. Write failing response-contract tests with synthetic sensitive values.
4. Implement the smallest allowlist and stock-model-aware projection in existing owners.
5. Add schema changes only if a demonstrated missing stock-model contract requires them; include migration and pgTAP tests.
6. Run focused tests, full test suite, TypeScript/build, Supabase reset and pgTAP.
7. Review diff for accidental public field exposure, service-role use, stale stock behavior and duplicate counting.
8. Keep the branch unmerged until Build 004 dependency is integrated and the PR is reviewed.

## 7. Explicit stop conditions

Stop and report rather than improvise if:
- the current public route contract is relied on by an unknown consumer and a response change would be breaking;
- aggregate-versus-serialized stock model cannot be determined from trusted persisted data;
- availability logic is duplicated or inconsistent across views/RPCs;
- the change requires a new privileged inventory RPC before Build 004 identity integration;
- a public endpoint must expose per-unit identity to satisfy an unverified requirement;
- a migration would duplicate an existing table/function or require production data repair.

**Decision:** B008-P0-01 is the first bounded implementation package. It is prepared with exact target routes and tests, but actual code changes wait until the current source contract and Build 004 integration boundary are approved. No production changes are made by this package document.
