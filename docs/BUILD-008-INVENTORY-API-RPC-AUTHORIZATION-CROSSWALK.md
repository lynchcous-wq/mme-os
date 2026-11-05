# Build 008 — Inventory API, RPC and Authorization Crosswalk

**Review branch:** `build-008-inventory-foundation`  
**Inspected base:** `integration/build001-catalog-inventory`  
**Purpose:** Establish exact ownership and authorization boundaries before additive Build 008 implementation.  
**Status:** Read-only code review; no production or database changes.

## 1. Verified API surface

| Route | Method | Observed behavior | Authorization / boundary finding |
|---|---|---|---|
| `/api/catalog` | GET | Reads commerce products, catalog products, balances, locations, categories and serialized units; composes public listing and availability | Uses server-side service-role REST calls. No caller authentication is visible in this handler. Must remain an explicitly public allowlisted projection; review every selected field and serialized-vs-aggregate quantity calculation. |
| `/api/catalog/[id]` | GET | Loads active commerce product, published catalog data, location availability and media | Server-side service-role read. Validates UUID and published/active product state. Public response must exclude supplier, cost, IMEI/serial, restricted inspection and internal unit fields. |
| `/api/catalog/[id]/units` | GET | Returns in-stock serialized unit IDs, location IDs/names and condition grades for active serialized products | Public-facing route uses service-role reads. Opaque unit IDs are still internal identifiers; review whether the storefront actually needs per-unit disclosure. Never add serial/IMEI to this response. Consider aggregate availability instead. |
| `/api/employee/inventory/inspection` | POST | Submits inspection via RPC | In this inspected base, comments and actor attribution use Auth user UUID as inspection identity. This is a pre-Build-004 pattern and must not be treated as canonical after Identity Matrix integration. |
| `/api/employee/inventory/inspection/resolve` | POST | Checks legacy approval and resolution permission RPCs, then resolves disposition | Inspected base attributes actor and approver with Auth user UUID. Build 004 branch adds identity-aware dual authorization; do not regress to this legacy-only implementation. |
| `/api/employee/inventory/inspection/history` | GET | Reads inspections by inspector and filters records through a legacy view permission RPC; reads related disposition records | Uses Auth user UUID as identity and per-row legacy authorization. Requires Build 004 identity/scope parity and query-level access review. |
| `/api/employee/inventory/inspection/photos` | POST | Loads inspection, checks owner/pending state, checks legacy submit permission, validates/uploads photo evidence and registers metadata | Owner check and actor fields use Auth user UUID in this base. Preserve private bucket and evidence safeguards while migrating actor identity to the distinct person identity mapping. |

The three catalog handlers are not employee mutation routes. Their service-role reads bypass browser RLS and therefore rely on server-side allowlisting, safe response shaping, and environment-secret protection. They must never return privileged inventory details simply because the service role can read them.

## 2. Verified database ownership and RPC contracts

| Domain | Existing owner | Verified server RPCs / tables | Required handling |
|---|---|---|---|
| Serialized inventory | `mme_serialized_units`, `mme_serialized_unit_reservations` | `mme_receive_serialized_unit` | Existing RLS enabled; direct anon/authenticated access revoked; service_role access granted. Serial/IMEI columns are text in inspected migration. |
| Aggregate receipt and movement | `mme_inventory_receipts`, `mme_inventory_movements`, existing inventory balances | `mme_receive_inventory`, `mme_adjust_inventory`, `mme_transfer_inventory` | Security-definer RPCs; execute revoked from public/anon/authenticated and granted to service_role. Server must perform employee permission and approval checks before privileged RPC invocation. |
| Order reservation/payment | Existing order and reservation tables | `mme_release_order_reservation`, `mme_expire_inventory_reservations`, `mme_process_verified_payment_event` | Server-only RPCs. Preserve verified payment webhook boundary, idempotency and transactional state checks. |
| Landed cost | `mme_inventory_landed_cost_pools`, `mme_inventory_landed_cost_allocations` | `mme_receive_inventory_with_landed_cost` | Server-only. Supported allocation methods in inspected migration are `extended_acquisition_value` and `equal_per_unit`. |
| Cross-channel stock claims | `mme_channel_stock_claims`, `mme_channel_stock_claim_lines` | `mme_create_channel_stock_claim`, `mme_release_channel_stock_claim`, `mme_expire_channel_stock_claims`; service-role view `mme_inventory_available_to_sell_v` | Server-only. Claims cover customer_hold, pos_quote, subscription, auction and manual_allocation. Must be reconciled with order reservations to prevent double reservation. |
| Serialized transfers/status | `mme_serialized_unit_movements` | `mme_transfer_serialized_units`, `mme_change_serialized_unit_status` | Server-only. Preserve movement history and verify state transition/authorization before reuse. |
| Inspection disposition | `mme_serialized_unit_dispositions` | `mme_resolve_serialized_inspection` | Disposition ledger is append-only; direct mutation privileges are revoked from service_role in the immutable-ledger migration. Corrections must use approved compensating processes, not direct edits. |

**Important:** A service-role-only RPC grant is a database execution boundary, not proof that the application caller was authorized. The trusted server route must authenticate the caller, resolve the canonical MME person identity, verify active employment/role/action/resource/location scope and approvals, then invoke the RPC. Never expose service-role keys to clients.

## 3. Identity integration delta

The inspected Build 001 employee inspection handlers contain legacy assumptions that Auth user UUID is the employee/inspection identity UUID. Build 004 explicitly separates the Supabase Auth subject from `mme_person_identities.id` and resolves the mapping server-side.

Therefore:
- Use the Build 004 identity helper and its canonical identity UUID for all new actor, approver and audit fields.
- Do not copy `auth.users.id` into identity foreign-key columns unless the schema explicitly defines that exact reference.
- Preserve legacy authorization checks until approved parity/cutover; dual authorization remains required during transition.
- Do not implement Build 008 employee inventory mutations against the legacy-only route patterns.
- Build 004 PR #14 remains draft/unmerged; this crosswalk does not authorize a production permission cutover.

## 4. Transaction and state ownership rules

1. Product catalog identity and published public product content remain catalog-owned.
2. Aggregate balance and serialized unit records are distinct physical stock representations. A serialized product must not be counted again through aggregate quantity unless its domain contract explicitly defines the reconciliation.
3. Order reservations, cross-channel claims, payment, order, shipment and pickup are separate states. A claim is not a sale; a payment event is not an inventory movement unless the owning transaction commits it.
4. Existing RPCs use row locking in important mutation paths. Build 008 must preserve lock ordering, atomicity, replay handling and compensating ledger semantics; it must not perform read-modify-write in route code.
5. Receipt, landed-cost pool and allocation must stay transactionally bound. Any new cost method requires source basis, approved method version, currency, deterministic rounding and residual reconciliation.
6. Serialized disposition history is append-only. Build 008 analytics and reporting must read it without mutating it.
7. Inventory event/task delivery belongs to Build 006; inventory state must remain correct if notification delivery fails.

## 5. Open implementation risks to resolve before adding routes

- **Public unit endpoint:** Confirm whether exposing opaque serialized unit IDs and precise location identifiers is necessary. Prefer aggregated public availability unless unit-level disclosure is a verified product requirement.
- **Catalog availability composition:** Inspect full query semantics and ensure aggregate and serialized stock are not double-counted. Validate stale/unknown location behavior and publication gating.
- **Legacy actor identity:** Replace Auth UUID assumptions only through the approved Build 004 migration path; keep legacy checks during dual-control period.
- **Scope provenance:** Inventory mutations must derive product/location/employee scope from trusted database rows, not caller-supplied JSON fields.
- **Cross-channel/order overlap:** Specify atomic conversion between claims and order reservations before adding any new hold type.
- **Serial/IMEI protection:** Define encryption, masking, privileged lookup, audit, export controls and retention; current text columns alone do not establish those controls.
- **Cost allocation expansion:** No weight/volume method should be exposed until approved by Accounting and implemented/tested in the existing landed-cost owner.
- **Live integration evidence:** Run real local-Supabase route-level tests for both authorized and denied users, terminated/frozen identities, scope mismatch, service outage and malformed/missing records. Existing mocked route tests and the current auth/RPC smoke test do not establish full route coverage.

## 6. Proposed Build 008 change boundary

Build 008 should add only missing capabilities after owner approval. Likely extension areas are:
- restricted serial/IMEI protection and purpose-limited access;
- explicit product-vs-unit and aggregate-vs-serialized reconciliation contracts;
- approved alternative landed-cost allocation methods and provenance;
- consistent public availability projection and freshness guarantees;
- inventory exception/read projections that reuse existing ledger and Build 006 task ownership;
- missing integration adapters after Build 007 CRM and Build 017 contracts are verified.

Do not create new competing product, serialized-unit, inventory-balance, movement, reservation, cross-channel claim, payment, receiving or disposition tables.

**Review result:** The repository has server-only RPC boundaries and broad existing Build 001 functionality, but application-level identity migration and public response minimization remain key integration controls. This document is a code-review crosswalk, not proof of production security or deployed behavior.
