# Build 008 — Acceptance Criteria to Existing Test Coverage Matrix

**Inspected test base:** `integration/build001-catalog-inventory`  
**Specification:** `docs/BUILD-008-ENTERPRISE-INVENTORY.md`  
**Status:** Test inventory and gap plan; no claim that every acceptance criterion is implemented or fully behavior-tested.

## 1. Existing test assets

The inspected branch contains **95 files under `supabase/tests/`**, including broad Build 001 inventory and catalog coverage. The inventory-relevant files below were confirmed by repository tree inspection.

| Domain / acceptance area | Existing tests | Coverage interpretation |
|---|---|---|
| Product catalog and catalog/commerce relationship | `product_catalog_foundation.sql`, `catalog_corrections_and_revisions.sql`, `atomic_catalog_workflows.sql`, `build001_catalog_commerce_link_guard.test.sql` | Catalog foundation, revision and product/commerce linkage checks exist. Add route-level tests for public response minimization, active/published mismatch, version drift and public data leakage. |
| Serialized unit identity and checkout | `build001_serialized_units.test.sql`, `build001_serialized_checkout.test.sql`, `build001_serialized_unit_cost_profitability.test.sql` | Serialized unit and checkout contract tests exist. No evidence from these filenames alone that IMEI/serial encryption, key rotation, masked display, purpose-bound access, export audit or retention are proven. |
| Receiving and auction batch intake | `build001_receiving_adjustments_transfers.test.sql`, `build001_auction_batch_receiving.test.sql`, `build001_purchase_orders_receiving_invoice_match.test.sql`, `build001_receiving_reconciliation_controls.test.sql`, `build001_serialized_po_receiving_reconciliation.test.sql`, `build001_scanner_receiving_station.test.sql` | Strong schema/RPC and receiving controls exist. Add end-to-end evidence tests for partial shipment, duplicate scans, unknown SKU, invalid supplier docs, cost mismatch and failed receiving rollback. |
| Aggregate and serialized movement / transfer | `build001_multilocation_transfer_approval.test.sql`, `build001_serialized_unit_transfers.test.sql`, `build001_physical_stocktake_reconciliation.test.sql` | Transfer and reconciliation assets exist. Add concurrent dispatch/receipt tests, missing/extra/damaged in-transit unit scenarios and source/destination scope denial. |
| Reservations and cross-channel claims | `build001_inventory_orders.test.sql`, `build001_reservation_lifecycle.test.sql`, `build001_unified_reservation_expiration.test.sql`, `build001_cross_channel_inventory_claims.test.sql`, `build001_channel_claim_lifecycle_hardening.test.sql`, `build001_pos_payment_inventory_consumption.test.sql`, `build001_unified_mixed_inventory_payment.test.sql` | Includes claim lifecycle, ownership conversion, idempotent fingerprint and concurrent-safe expiry structural checks. Add live simultaneous checkout/quote/auction claim race tests, duplicate/out-of-order webhook replay and cross-ledger aggregate/serialized double-count prevention. |
| Landed cost / item cost | `build001_landed_cost_allocation.test.sql`, `build001_serialized_unit_cost_profitability.test.sql` | Existing supported allocation methods have tests. Build 008's weight/volume allocation, versioned basis, currency conversion, deterministic rounding/residual and changed-proposal invalidation need new tests if approved. |
| Inspection, repair, quarantine, disposition and evidence | `build001_inspection_damage_repair_quarantine.test.sql`, `build001_atomic_inspection_submission.test.sql`, `build001_private_inspection_storage_bucket.test.sql`, `build001_serialized_unit_disposition_ledger.test.sql`, `build001_return_inspection_refund_gate.test.sql`, `build001_returns_refunds_inspection_intake.test.sql` | Inspection and disposition foundations exist. Verify Build 017 contract and Build 004 identity integration; add end-to-end route-level tests for evidence authorization, photo content mismatch, actor identity mapping, unauthorized resolution and no auto-restock. |
| Barcode, labels and scanner | `build001_barcode_label_engine.test.sql`, `build001_barcode_scanner_cycle_counts.test.sql`, `build001_scanner_receiving_station.test.sql` | Label/scanner schemas and privilege boundaries are tested. No physical printer, calibration, logo rendering, 2×3 stock, QR default-off, density or reprint operator verification is established by database tests. |
| Cycle counts and variance | `build001_cycle_count_variance_posting.test.sql`, `build001_explicit_cycle_count_confirmation.test.sql`, `build001_physical_stocktake_reconciliation.test.sql` | Confirmation, approval/post privileges and audit controls exist. Add multi-counter blind-count, segregation-of-duties, snapshot drift, concurrent movement during count and high-value approval scenarios. |
| Replenishment and analytics | `build001_inbound_stock_aware_replenishment.test.sql`, `build001_inventory_dashboard_reorder_intelligence.test.sql`, `build001_inventory_control_center_kpis.test.sql`, `build001_inventory_executive_snapshot.test.sql`, `build001_inventory_financial_intelligence.test.sql`, `build001_inventory_forecasting_purchasing.test.sql`, `build001_inventory_sales_velocity_stock_cover.test.sql`, `build001_inventory_shrinkage_intelligence.test.sql`, `build001_inventory_transfer_recommendations.test.sql` | Governed reporting and forecast assets exist. Add independent formula fixtures, freshness/staleness tests, actual-vs-estimate labeling, valuation-date/currency boundaries and role/location row filtering. |
| Exceptions, notifications, fulfillment | `build001_inventory_exception_management.test.sql`, `build001_customer_fulfillment_notifications_pickup_verification.test.sql`, `build001_fulfillment_notification_worker_reliability.test.sql`, `build001_shipping_pickup_fulfillment.test.sql`, `build001_warranty_device_lifecycle.test.sql` | Exception and worker reliability foundations exist. Add provider outage/replay, durable task after notification failure, stale availability, pickup verification abuse and website publication reconciliation. |

## 2. Acceptance criteria with explicit new verification required

The following are not considered satisfied solely because related schema tests exist.

| Build 008 acceptance criterion | Existing foundation | New test/evidence required |
|---|---|---|
| No serial/IMEI leakage in public responses, logs, exports, labels | Serialized unit and catalog tests | API contract tests with seeded sensitive values across list/detail/unit/CSV/export/error/log surfaces; assert exact absence. |
| Encrypted, masked, purpose-limited identifier vault | Text serial/IMEI columns and access restrictions | Security design approval plus crypto/key integration tests, rotation, authorized reveal, masked response, access audit, denied bulk export and retention behavior. |
| All movement rows have actor, reason, source, timestamp and correlation | Existing movement/receipt/transfer/disposition records | Constraint and transaction tests for null/missing actor, missing reason/source, failed audit write rollback and append-only history. |
| Cost pool provenance and CEO approval bound to exact version | Existing landed-cost pools and allocations | Tests for modified proposal invalidating approval, allocation method/version preservation, multi-currency rejection/FX source, deterministic residual handling. |
| Weight/volume cost allocation | Not in currently verified methods | Add only after Accounting approval; test validated measurements, zero/negative/unknown basis, mixed units, rounding and direct-attributable cost. |
| Atomic receiving and inspection release | Existing receiving and inspection tests | Real local-Supabase transaction tests for failed condition/evidence/cost gates and no partial stock release. |
| Concurrent stock reservations cannot oversell | Existing reservations/claims tests and locking | True concurrent clients against local Supabase, including aggregate and serialized stock and cross-channel claims. |
| Transfers reconcile transit and destination receipt | Existing transfer tests | Concurrent and fault-injection tests for partial receipt, missing/extra/damaged units, duplicate delivery, timeout/retry and source/destination scope. |
| Coming Soon cannot be purchased before receipt/inspection/price approval | Catalog/publication foundations | Website/API integration tests proving pre-receipt listing is informational only and stale publication cannot accept immediate checkout. |
| 2 × 3 physical labels and printer verification | Label database tests | Hardware-in-loop verification with selected printer, paper, logo, QR off, auto density, scanner readability, reprint audit and operator signoff. |
| Count discrepancy cannot be erased | Cycle count tests | Blind count and segregation-of-duties tests; expected snapshot immutability; count-vs-movement race; variance approval and compensating adjustment audit. |
| Return and refund remain separate; no auto-restock | Returns/refund gate tests | Full return lifecycle with separate payment and stock states, Build 017 inspection contract, failed refund, failed disposition, damaged/quarantine and retry. |
| BI values reconcile and label estimates/staleness | Existing analytics tests | Independent calculation fixtures with valuation date, source freshness, currency, status inclusion, role/location filtering and export control. |
| Build 006 tasks durable and idempotent | Fulfillment notification worker tests and inventory exception tests | Outbox/event replay, duplicate event, task delivery outage, retry exhaustion, dead-letter/recovery and correlation to inventory source event. |
| GitHub Actions cannot mutate production inventory | Workflow/security documentation | CI policy test and environment review; prove no production service-role credential or inventory-write step exists in validation workflows. |

## 3. Build 004 / Build 007 dependency tests

Build 008 cannot treat identity and CRM dependencies as ordinary unit-test prerequisites.

### Build 004 identity
- Real Auth subject maps to a distinct MME person identity.
- Active employee, role, assignment, effective date, action and location scope are checked server-side.
- Terminated, suspended, frozen, unassigned, expired and mismatched-scope users are denied.
- CEO exception is narrowly scoped and remains subject to required active identity/employee/freeze controls.
- Auth service or authorization RPC outage fails closed.
- Legacy permission parity remains active until approved cutover.
- Route tests cover receive, inspect, transfer, reserve, count, approve, adjust, write-off, export and identifier reveal.

### Build 007 CRM
- Customer account, customer relationship and employee relationship remain distinct concepts.
- Customer/quote/lead ownership references are stable, versioned and independently permissioned.
- Customer-held stock/quote holds map to the existing cross-channel claim owner; no duplicate CRM stock ledger.
- Customer consent/communication references are minimal, access-controlled and auditable.
- CRM outages do not silently release or corrupt existing inventory reservations.

## 4. Prioritized new test packages

1. **P0 — Identity and public data safety:** Build 004 route-level authorization matrix; public catalog/serialized-unit response leak tests; service outage fail-closed behavior.
2. **P0 — Stock integrity:** aggregate/serialized double-count invariants; real concurrent reservation/claim races; order conversion idempotency; verified payment replay.
3. **P0 — Movement and receiving:** transactional rollback, missing audit attribution, receiving partial/duplicate/unknown units, transfer transit discrepancies.
4. **P1 — Identifier protection:** encryption, key rotation, masked display, purpose-limited reveal, export/access audit, retention.
5. **P1 — Cost and approval integrity:** item-level basis, approval version drift, method version, rounding/residual, multi-currency.
6. **P1 — Cycle count and returns:** blind count, snapshot drift, segregation-of-duties, Build 017 inspection and refund/disposition separation.
7. **P1 — Publication and fulfillment:** Coming Soon purchase blocking, stale availability, website sync reconciliation, Build 006 durable task delivery.
8. **P2 — Physical device validation:** label hardware, scanner symbology, print calibration, operator confirmation and reprint handling.
9. **P2 — Analytics correctness:** independent KPI formulas, source/freshness/valuation semantics, scoped exports.

## 5. Evidence and scope limitations

- The test inventory was inspected on branch `integration/build001-catalog-inventory`; this is not proof that every listed file runs successfully in the current Build 008 branch.
- Some tests use structural catalog checks against function definitions and privileges. Those are useful guardrails but are not equivalent to exercising all runtime branches.
- No physical printer/scanner, website provider, CRM provider or production inventory environment was tested in this audit.
- The Build 004 live Supabase smoke test currently proves real Auth sign-in, distinct identity mapping, one denied authorization RPC and invalid-token rejection. It does not yet exercise every inventory HTTP route or full authorization matrix.
- Build 007 is still specification/dependency-review only in the inspected branch; CRM integration acceptance tests cannot pass until its approved schema and API contracts exist.

**Result:** Build 001 already has broad database test coverage. Build 008's next work is to close integration, security, concurrency and physical-verification gaps—not duplicate existing tests or claim the specification is complete.
