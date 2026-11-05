# Build 008 — Pre-Implementation Dependency and Repository Readiness Review

**Build:** 008 — Enterprise Inventory Management & Product Intelligence Engine  
**Review branch:** `build-008-inventory-foundation`  
**Specification:** `docs/BUILD-008-ENTERPRISE-INVENTORY.md`  
**Review status:** Architecture reviewed; implementation is not authorized by this review  
**Decision:** Begin Build 008 with repository/dependency preparation only. Do not create inventory migrations or runtime services until the blocking upstream contracts are approved.

## 1. Verified repository state

The inspected `build-008-inventory-foundation` tree contains the storefront shell and documentation for Builds 001–008. It contains no Build 008 inventory migrations, inventory API routes, inventory service implementation, inventory UI, inventory movement ledger, receiving workflow, reservation service, barcode/label implementation, or integration tests.

The inspected `implementation/build-007-crm-foundation` tree contains the Build 007 CRM specification and identity-dependency review, but no dedicated CRM schema, CRM API, CRM UI, lead/opportunity/interaction service, telephony integration, or CRM runtime tests. The Build 007 specification explicitly labels itself **not implemented**.

This review does not infer implementation from branch names, roadmap documents, or existing Build 001 inventory-related features. Existing Build 001 catalog/order/inventory capabilities must be inventoried and reused rather than duplicated.

## 2. Dependency gate

Build 008 declares dependencies on Builds 001–007. The immediate blocking dependency is Build 007's customer/CRM integration contract, together with the Build 004 identity integration gate.

| Dependency | Required contract for Build 008 | Current evidence | Gate |
|---|---|---|---|
| Build 001 — Catalog / commerce / inventory foundations | Stable Product ID, product version, unit identity boundaries, order/POS ownership, catalog publication contract | Existing Build 001 code/migrations/tests are present in integration history; inventory-related capabilities already exist and require reuse audit | Verify exact interfaces and avoid duplicate stock/order ledgers |
| Build 002–003 — Platform / interface | Approved application boundaries and UI conventions | Documentation and storefront shell exist | Verify actual reusable components before UI work |
| Build 004 — Identity Matrix | Opaque person identity, active employee relationship, scoped role/action/location authorization, whole-login lock, server-side enforcement | Build 004 implementation is in draft PR #14; CI passed at the validated code commit, but PR remains open/draft/unmerged and production cutover is not approved | Blocking for privileged inventory routes and employee attribution |
| Build 005 — Executive dashboard | Governed reporting projections and KPI ownership | Existing dashboard build files/docs are present | Reuse only approved read contracts; inventory remains source of truth |
| Build 006 — Task / notification / workflow engine | Durable task/event contracts, idempotency, escalation and failure handling | Existing workflow engine migrations and tests are present in the integrated repository | Verify event contract and authorization before emitting inventory tasks |
| Build 007 — Enterprise CRM | Stable customer relationship reference, customer/employee relationship separation, lead/quote/customer ownership contracts, consent/communication references | Specification and dependency review only; no CRM implementation or approved CRM schema/API | Blocking for CRM-linked inventory reservations, customer attribution and quote-hold integration |
| Build 017 — Returns/condition inspection | Verified inspection and disposition contract | Referenced by Build 008 roadmap; implementation/interface not verified | Do not implement return disposition integration until verified |

## 3. Existing Build 001 overlap audit required

Build 008 must not introduce a second product catalog, order ledger, inventory quantity authority, payment status authority, or duplicate serialized-unit record. Before schema work, inspect and map at least:

- Product catalog and product-version tables, category attributes and public listing state.
- Existing inventory unit/serialized identifier tables and inspection records.
- Inventory order, reservation, movement, location, transfer and adjustment functions/tables, if present.
- POS/checkout and payment transaction boundaries.
- Acquisition/COGS and landed-cost records, if present.
- Existing inspection photo/evidence storage and disposition ledger.
- Existing website publication/availability endpoints and webhook handlers.
- Existing Build 006 workflow event/task APIs.
- Existing permission checks and audit events.

For each capability, record its authoritative table/service, current consumers, migration ownership, tested RPC/API, and gaps. Reuse or extend the existing owner. Do not add parallel tables until the audit demonstrates a distinct missing domain and the owner approves the boundary.

## 4. Safe Build 008 work that can begin now

The following work can proceed without claiming Build 007 completion or bypassing Build 004:

1. **Read-only repository inventory:** document current catalog, serialized-unit, inspection, order, reservation, location, COGS, pricing and workflow assets.
2. **Domain crosswalk:** map every Build 008 requirement to an existing owner or an explicit gap; distinguish reuse, extension and genuinely new capabilities.
3. **API/event contract drafts:** define proposed command/query/event shapes with versioning, idempotency, trusted scope, actor identity, audit correlation and failure behavior. Mark them proposed until owners approve.
4. **Threat model and data classification:** map serial/IMEI, supplier documents, cost, pricing, customer references and public product data; specify field-level access and leakage tests.
5. **Test plan:** design concurrency, stale availability, duplicate identifier, ledger immutability, unauthorized scope, receiving/inspection, transfer reconciliation and reservation idempotency tests.
6. **Hardware/provider verification plan:** record label dimensions (2 × 3 inches), logo enabled, QR disabled by default and automatic density as requested; do not claim printer compatibility until hardware is identified and physically tested.

No inventory schema, migration, route, UI or production configuration is created by this readiness review.

## 5. Required gates before Build 008 implementation

- [ ] Build 004 identity migrations and authorization contract are integrated into the approved base and database-backed security tests pass.
- [ ] Build 007 CRM schema/API ownership is approved and implemented sufficiently to expose stable customer relationship and quote/customer references; tests prove customer and employee relationship independence.
- [ ] Build 001 catalog/order/inventory overlap audit is complete and signed off.
- [ ] Build 006 event/task contracts are verified for durable inventory exceptions.
- [ ] Build 017 status and returns/inspection disposition contract are verified, or the initial Build 008 scope explicitly excludes returns integration.
- [ ] Product/unit IDs, serialized identifier vault, inventory ledger, location hierarchy and reservation transaction boundary are approved.
- [ ] Acquisition/COGS, pricing, website, POS/Deal Desk, shipping and label provider contracts are verified before connecting them.
- [ ] Migration, rollback, concurrency, backup/recovery, synthetic-data and staged-release plans are reviewed.

## 6. Recommended implementation sequence after gates

1. Reconcile and extend Build 001 catalog/product/unit foundations; establish product-versus-unit invariants.
2. Implement or harden the append-only inventory movement ledger, status transitions and location scope.
3. Implement receiving and condition inspection with restricted identifier handling and evidence.
4. Implement transfer, cycle-count, adjustment and reconciliation workflows.
5. Implement reservation/availability commands with atomic concurrency control and idempotency.
6. Integrate approved acquisition/COGS and pricing contracts with version-bound approval.
7. Integrate website, POS, Deal Desk, shipping, Build 006 workflows and verified Build 017 disposition contracts.
8. Add label/printing support, governed analytics and controlled AI assistance.
9. Complete negative/security/recovery tests, hardware verification, review and staged release.

## 7. Security and rollout boundary

- Customer, employee and inventory authorization must be server-side and scoped; UI visibility and barcode scans are not permissions.
- Request-supplied customer, employee, product, location, cost or approval fields are not trusted authorization evidence.
- Serial/IMEI, supplier documents, internal cost and customer relationship data must not appear in public APIs, logs, GitHub artifacts or ordinary notifications.
- Inventory changes require atomic state transitions, idempotency, actor attribution, reason, source reference and immutable/compensating audit history.
- GitHub Actions may validate code and migrations; they must not write production inventory directly.
- No production migration, provider activation, live inventory synchronization or deployment is authorized by this document.

**Current decision:** Build 008 is now in pre-implementation readiness and dependency reconciliation. Its architecture specification is present, but implementation remains gated by Build 004 integration, Build 007 CRM implementation/contracts, and the Build 001 overlap audit.