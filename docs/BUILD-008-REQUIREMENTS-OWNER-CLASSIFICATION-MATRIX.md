# Build 008 — Requirements-to-Owner and Implementation Classification Matrix

**Branch:** `build-008-inventory-foundation`  
**Specification baseline:** `docs/BUILD-008-ENTERPRISE-INVENTORY.md`  
**Evidence sources:** Build 001 migration/API/test inspection, Build 004 readiness review, Build 007 repository inspection, and the Build 008 crosswalk/test/transaction documents.  
**Status:** Classification and sequencing proposal; not implementation authorization.

## 1. Classification rules

- **A — Existing owner:** A capability is already represented in the inspected Build 001 repository. Build 008 should reuse it, not create another system of record. This does not mean production deployment or full acceptance is verified.
- **B — Harden/integrate existing owner:** A foundation exists, but the specification requires additional controls, API integration, security, concurrency, operational evidence or tests.
- **C — New capability:** No sufficiently matching implementation was verified in the inspected repository. A new capability may be designed only after its owning domain and dependencies approve the contract.
- **G — Gated:** Work depends on Build 004 identity integration, Build 007 CRM implementation, Build 017 returns contract, or a provider/hardware decision. Gated does not mean impossible to design; it means production implementation/integration cannot be claimed.

## 2. Requirements matrix

| Build 008 requirement | Authoritative owner | Class | Verified evidence / gap | Implementation direction |
|---|---|---:|---|---|
| Stable Product ID, catalog descriptions, media, category/model attributes | Build 001 Catalog | A/B | Catalog tables, APIs, revision and commerce-link tests exist; verify all category schemas/version contracts | Reuse catalog IDs and versioning; add only missing category validation |
| Product versus physical unit distinction | Build 001 Inventory | A/B | `mme_serialized_units` and catalog-unit linkage exist; aggregate-vs-serialized invariants need end-to-end proof | Formalize stock model per product and prevent double-counting |
| Aggregate stock balances and movement history | Build 001 Inventory | A | Balance, receipt and movement records/RPCs and tests exist | Reuse existing tables/RPCs; no second stock ledger |
| Serialized physical units and unit movements | Build 001 Inventory | A/B | Unit, transfer and disposition foundations exist; restricted identifier protection not proven | Reuse unit IDs and movements; harden identifier storage/access |
| Condition grades, inspection and quarantine | Build 001 Inspection / Build 017 | A/B/G | Inspection, repair, quarantine, photo evidence and disposition tests exist; Build 017 ownership/interface must be verified | Reuse inspection/disposition; align grade vocabulary and Build 017 |
| Receiving and purchase-order reconciliation | Build 001 Inventory / Acquisition | A/B | Receipt RPCs, auction/PO receiving and reconciliation tests exist | Harden duplicate scans, discrepancy evidence, rollback and authorization |
| Transfers and in-transit reconciliation | Build 001 Inventory | A/B | Aggregate and serialized transfer foundations/tests exist | Reuse existing transfer owner; verify dispatch/receipt state machine and concurrency |
| Inventory adjustment and cycle counts | Build 001 Inventory | A/B | Adjustment, stocktake, cycle-count confirmation and variance posting tests exist | Harden blind counts, segregation, snapshot drift and approval thresholds |
| Order reservation and expiry | Build 001 Order/Inventory | A/B | Reservation lifecycle, expiry, payment consumption tests exist | Reuse; add real concurrent checkout and expiry/payment race tests |
| Cross-channel claims (customer hold, POS quote, subscription, auction, manual allocation) | Build 001 Inventory | A/B/G | Cross-channel claim tables/RPCs/tests exist; CRM source ownership and atomic conversion contract require proof | Reuse claim ledger; define one atomic claim-to-order conversion; wait for Build 007 for CRM-owned references |
| Serialized checkout and payment consumption | Build 001 Inventory + Payments | B/G | Serialized foundation explicitly defers checkout; existing payment reservation consumption is aggregate oriented | Do not enable until atomic unit reservation/payment/expiry/refund-recovery contract and tests exist |
| Verified payment event and order consumption | Payments Center / Build 001 Order | A/B | Verified payment-event RPC and inventory consumption tests exist | Reuse; harden signature boundary, replay, out-of-order and late-payment cases |
| Acquisition batch, supplier evidence, item-level COGS | Acquisition/COGS | B/G | Landed-cost pool/allocation foundation exists; complete acquisition evidence workflow/approved integration not established | Verify acquisition owner and source records; do not create competing cost source |
| Landed-cost allocation by extended value/equal unit | Build 001 Landed Cost / Accounting | A | Both methods are represented in existing RPC and tests | Preserve existing methods and historical method versions |
| Weight, volume and other allocation bases | Accounting / Acquisition | C/G | Not supported by the verified landed-cost method contract | Design only after Accounting approves measurement, versioning, currency and rounding policy |
| CEO approval bound to exact acquisition/cost proposal version | CEO Approval / Acquisition | B | Existing approval foundations may cover parts; end-to-end version invalidation needs proof | Harden version-bound approval and change invalidation; no AI auto-approval |
| Approved selling price and markdown rules | Pricing System | B/G | Pricing integration/approval ownership is specified but not verified as a complete active service | Integrate the existing Pricing owner; do not let inventory set price |
| Website product listing/publication | Build 001 Catalog / E-commerce | A/B/G | Catalog APIs and storefront shell exist; provider platform and live sync not verified | Reuse public catalog projection; verify provider and add authenticated idempotent sync |
| Coming Soon listing and checkout block | Catalog/E-commerce + Inventory | B/G | Specification defines lifecycle; end-to-end publication/checkout proof not verified | Add versioned eligibility checks and tests after e-commerce contract is confirmed |
| Public availability and stale-data policy | Build 001 Inventory / Catalog | B | Public catalog reads and availability composition exist; serialized unit endpoint exposes opaque unit/location identifiers | Minimize public projection; aggregate availability, freshness and fail-safe behavior |
| Serial/IMEI encryption, masking, purpose-bound reveal, export audit | Security / Identity / Inventory | C/G | Existing text columns and access restrictions do not prove encryption/masking/rotation or purpose audit | New security capability in existing unit owner; approve key management and retention first |
| Barcode/label database service | Build 001 Inventory / Brand Settings | A/B | Barcode label engine and scanner tests exist; actual printer compatibility not verified | Reuse label engine and brand asset reference; add safe serial reference and versioned label fields |
| Physical 2×3-inch printing, logo, QR-off, auto density | Operations / Hardware | B/G | User settings are specified; no physical hardware test evidence | Hardware-in-loop test on selected printer/stock/driver with operator signoff |
| Inventory analytics, reorder, forecasting, shrinkage, stock cover | Build 001 BI / Build 005 | A/B | Numerous KPI/forecast/shrinkage/transfer recommendation tests exist | Reuse governed projections; verify formula, source freshness, role scope and estimates |
| Durable inventory tasks and exception notifications | Build 006 Workflow | A/B/G | Inventory exception and worker reliability foundations/tests exist | Reuse Build 006 event/task owner; verify outbox durability, retries and dead-letter replay |
| Customer relationship and quote/lead ownership references | Build 007 CRM | G | Build 007 is specification-only in inspected branch; no CRM schema/API/runtime verified | Block CRM-linked holds/quote attribution until CRM schema/API is implemented and approved |
| Employee identity and location/action authorization | Build 004 Identity Matrix | G | Build 004 work is in draft PR #14; real Auth-to-person mapping/RPC smoke test exists but complete route-level authorization matrix remains outstanding | Continue dual checks; no production cutover or privileged Build 008 route until approved |
| Return eligibility, refund and stock disposition separation | Returns / Build 017 + Payments + Inventory | B/G | Existing return inspection/refund gate and disposition foundations/tests exist; Build 017 interface not verified | Reuse current owners; verify Build 017 contract and ensure refund never implies restock |
| GitHub protected deployment, secret and workflow governance | Repository Administration / Security | B/G | CI workflows exist; repository plan/settings and production topology require inspection | Verify actual controls; CI validates code, never writes production inventory |
| Backup/restore, recovery objectives, inventory reconciliation | Platform Operations / Inventory | B/G | Recovery/reconciliation elements exist in migrations/docs; approved RTO/RPO and restore drill not evidenced | Define owners and RTO/RPO; test restore and stock reconciliation before release |
| AI research and product/cost suggestions | Acquisition Intelligence / AI Governance | C/G | AI assistance is specified; no approved runtime/integration contract verified | Human-reviewed suggestions only; source/time/confidence and kill switch; no purchasing/pricing/release authority |

## 3. Capability summary

This is a qualitative classification, not a delivery percentage or proof of completion:

- **A — Existing owner:** Product/catalog, core stock/movement, serialized unit, receiving, transfer, reservation/claim, payment-event, inspection/disposition, label engine and inventory analytics foundations.
- **B — Harden/integrate:** Public availability, concurrency and claim conversion, receiving evidence, transfer reconciliation, cycle-count controls, cost approval/versioning, pricing/publication sync, workflow durability, return integration, GitHub governance and recovery.
- **C — New capability:** Protected serial/IMEI vault controls, approved additional landed-cost allocation methods, and scoped AI research assistance (subject to confirming no existing equivalent elsewhere).
- **G — Gated:** Build 004 identity integration, Build 007 CRM references, Build 017 return inspection contract, provider choices, printer hardware and production operations approvals.

Do not interpret A as production-ready or B as implemented. Classification reflects inspected repository evidence only.

## 4. Implementation sequencing and release gates

### Phase 0 — Dependency clearance
1. Build 004 identity: integrate approved person identity and server-side action/location scope; complete live route-level authorization tests; retain legacy checks until formal cutover approval.
2. Build 007 CRM: implement approved customer/quote/lead references and prove customer relationship data is distinct from employee identity.
3. Build 017: verify return inspection/disposition interface and ownership.
4. Build 001 audit: approve the complete table/RPC/API crosswalk and aggregate/serialized stock invariant.
5. Provider/hardware: verify e-commerce, pricing, payment, shipping and label hardware contracts before enabling integrations.

### Phase 1 — P0 stock and privacy hardening (existing owners)
1. Public response allowlisting and serial/IMEI leakage tests.
2. Aggregate/serialized stock reconciliation and double-count prevention.
3. True concurrent reservation/claim/expiry/payment race tests.
4. Atomic claim-to-order conversion contract.
5. Receiving/adjustment/transfer rollback and actor/audit attribution.
6. Build 004 route authorization matrix.

### Phase 2 — Financial and lifecycle integrity
1. Acquisition and landed-cost source provenance.
2. Version-bound CEO approval and method-version preservation.
3. Accounting-approved weight/volume method design if still required.
4. Cycle-count blind/segregation controls.
5. Returns/refund/disposition separation and Build 017 integration.

### Phase 3 — Channels and operations
1. Website/Coming Soon publication and stale availability policy.
2. CRM customer/quote hold integration.
3. Build 006 durable task/event integration.
4. Physical label/printer verification.
5. Shipping, pickup and provider reconciliation.

### Phase 4 — Intelligence and controlled release
1. Governed analytics formulas and freshness.
2. Scoped AI research suggestions with human approval.
3. Security, backup/restore, incident and recovery tests.
4. Staged release, operational training and evidence review.

## 5. Explicit no-duplicate and no-bypass rules

- Do not create a new product catalog, serialized-unit table, aggregate balance table, movement ledger, reservation ledger, channel claim ledger, payment state, landed-cost pool or disposition ledger.
- Do not use a service-role RPC grant as a substitute for authenticating and authorizing the employee.
- Do not use Auth subject UUID where the schema requires MME person identity UUID.
- Do not let public catalog endpoints expose serial/IMEI, internal unit IDs, supplier records, cost, inspection evidence or employee data.
- Do not convert a claim by releasing stock and then creating a new reservation in a separate transaction.
- Do not enable serialized online checkout through the aggregate reservation/payment path.
- Do not mark payment/refund complete based solely on inventory state.
- Do not create weight/volume allocation methods without Accounting approval.
- Do not treat Coming Soon as immediately purchasable stock.
- Do not claim printer, provider, production, or deployment readiness without actual verification.

## 6. Decision

**Build 008 should proceed as an integration and hardening program over Build 001, not as a greenfield inventory build.** The first executable P0 package should be public data minimization and stock-model invariants only after Build 004 identity dependencies are integrated and the relevant current branch/base is selected. CRM-linked inventory flows remain blocked until Build 007 is implemented. No runtime code or production changes are authorized by this matrix.
