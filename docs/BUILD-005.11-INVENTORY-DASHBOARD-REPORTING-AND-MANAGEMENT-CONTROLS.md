# Build 005.11 — Inventory Dashboard, Reporting, and Management Controls

**Status:** Dashboard and reporting design only  
**Branch:** `implementation/build-005-inventory-core`  
**Scope:** Defines proposed inventory dashboards, reports, filters, management controls, access boundaries, and acceptance criteria. No UI, API, database, permissions, analytics jobs, or deployments are implemented by this document.

## 1. Purpose

Define a consistent management view of MME inventory across stores, locations, serialized products, quantity-based stock, receiving, reservations, transfers, exceptions, and reconciliation.

The dashboard is a read-oriented operational view. Inventory Core remains the authority for stock state and all inventory mutations. Dashboard actions, when later implemented, must call approved server-side commands and must never write stock directly.

## 2. Dashboard audiences

| Audience | Default view | Access boundary |
|---|---|---|
| CEO / authorized executive | Enterprise overview, store comparison, high-risk exceptions, trend summaries | Executive scope explicitly granted by server-side permissions |
| General/store manager | Assigned store overview, receiving, availability, holds, transfers, counts, exceptions | Assigned location scope |
| Inventory manager | Inventory health, aging, discrepancies, movement and adjustment review | Approved inventory-management scope |
| Receiving associate | Expected receipts, receiving queue, discrepancies assigned to them | Assigned receiving location and task scope |
| Sales associate | Sellable availability and reservation status needed for sales | Minimal operational read access; no cost or protected identifiers by default |
| Finance/COGS reviewer | Approved acquisition-cost and inventory valuation reports | Separate finance permission; no automatic access to protected identifiers |
| IT/security operator | Service health, access-denial and integration failure signals | Technical diagnostics with sensitive-data redaction |

A title or dashboard selection does not grant access. The server resolves the actor and enforces permissions and location scope for every request.

## 3. Executive inventory overview

Proposed summary cards:
- Total sellable units/quantity by store and product family.
- Serialized unit count and quantity-lot count, shown separately.
- Available, reserved, held, quarantined, in-transit, and unavailable stock.
- Open receiving lines and overdue receipts.
- Open transfers and in-transit discrepancies.
- Open inventory exceptions by severity and age.
- Reconciliation status and last successful run.
- Outbox/event backlog and service-health indicators.

Each metric must show its definition, selected scope, as-of timestamp, and freshness state. Avoid presenting stale projections as live truth.

## 4. Store and location dashboard

Required views:
- Location-level stock summary.
- Inventory by category, brand, SKU, condition, and lifecycle status.
- Receiving and put-away queue.
- Transfers awaiting dispatch, receipt, or discrepancy resolution.
- Holds and quarantined stock with reason and assigned owner.
- Reservations nearing expiry and failed reservation attempts.
- Cycle-count schedule and open count variances.
- Exception queue with age, severity, and owner.

Filters:
- Store/location (only authorized scope).
- Product family/category/brand.
- SKU and condition grade.
- Serialized versus quantity-based inventory.
- Lifecycle status.
- Receipt, order, transfer, and case reference.
- Date range and aging band.
- Assigned employee/owner where permitted.

## 5. Inventory health and aging reports

### 5.1 Stock aging
Show age bands based on a documented event timestamp, such as received date or first sellable date. The report must identify which timestamp is used and must not mix definitions silently.

Suggested bands:
- 0–30 days
- 31–60 days
- 61–90 days
- 91–120 days
- 121+ days

### 5.2 Condition and inspection
Report counts by condition grade, inspection status, failed test category, unresolved defect, and quarantine reason. Do not infer product condition from price or sales status.

### 5.3 Availability
Show on-hand, reserved, held, quarantined, in-transit, and sellable balances separately. Define the formula and freshness window. Never label a product “available” solely because a stale cache shows a positive quantity.

### 5.4 Inventory movement
Summarize receipts, sales/commits, transfers, returns-to-stock, holds, releases, and adjustments. Provide drill-through to authorized movement records and source references.

## 6. Receiving and supplier reports

- Expected versus received quantities.
- Partial, short, over, damaged, and unidentified receipt lines.
- Receipt processing time and aging.
- Supplier/auction reference and acquisition batch reference.
- Discrepancy rate and unresolved discrepancy age.
- Receiving productivity metrics, where approved and fairly defined.

Do not calculate item landed cost by equally splitting a pallet purchase price across unlike products. Cost reporting must use the approved Acquisition/COGS allocation source and display its method and status.

## 7. Reservation and sales-channel reports

- Active reservations by channel and location.
- Reservations expiring soon.
- Reservation success/conflict/expiry counts.
- Committed versus released allocations.
- Website/POS/auction availability consistency.
- Orders blocked by insufficient eligible inventory.
- Duplicate request/idempotency conflict counts.

These reports explain inventory behavior; they do not prove payment capture, revenue recognition, or customer fulfillment. Those facts remain owned by the relevant order/payment/shipping systems.

## 8. Adjustment, transfer, and exception controls

Management review queue should include:
- Pending adjustment approvals.
- Large or repeated adjustment patterns.
- Transfers awaiting receipt or reconciliation.
- Repeated serial/IMEI conflicts.
- Count variances beyond approved thresholds.
- Long-running holds and quarantines.
- Critical/high exceptions and overdue cases.

For each record show the reason, evidence reference, requesting actor, location, timestamp, and approval status, subject to role permissions.

If approval actions are later implemented:
- require a fresh server-side authorization check;
- enforce separation of duties where policy requires it;
- record approver, decision, reason, and timestamp;
- use an idempotent command;
- preserve original movement history;
- never approve through a client-side status toggle.

## 9. Valuation and cost visibility

Inventory valuation is a controlled finance view, not a general sales dashboard field.

Requirements:
- Use approved acquisition/landed-cost records.
- Show cost method, source, currency, effective date, and allocation status.
- Distinguish unknown, pending, estimated, and approved cost.
- Never substitute retail price or market estimate for actual acquisition cost.
- Restrict cost and margin fields to explicitly authorized roles.
- Keep selling price, acquisition cost, landed cost, and valuation separate.
- Mark projections and estimates clearly; do not present them as actuals.

## 10. Export and report governance

- Exports must apply the same authorization and location filters as on-screen reports.
- Sensitive columns are excluded by default.
- Serial/IMEI values are masked or omitted unless a specific permission and business purpose allow access.
- Every export records actor, time, scope, report type, and applied filters.
- Large exports should be generated server-side with bounded scope and expiry.
- Do not place secrets, payment credentials, or unnecessary personal data in exports.
- Retention and download access must follow MME policy.

## 11. Dashboard performance and freshness

- Every metric exposes an as-of timestamp and freshness indicator.
- Operational decisions that affect a sale or handoff must revalidate through the authoritative service.
- Cached reports are for analysis, not mutation authorization.
- Heavy reports should use approved read models or asynchronous generation.
- Report failures must be visible and must not be shown as zero-valued success.
- Reconciliation drift and delayed event processing must be surfaced prominently.

## 12. Acceptance criteria

### Access and scope
- [ ] Server-side actor resolution is used for every protected dashboard request.
- [ ] Store managers cannot query unassigned locations.
- [ ] Sales roles cannot access cost, margin, or protected identifiers without explicit permission.
- [ ] Executive access is permission-based, not title-based.
- [ ] Exports enforce the same scope as the dashboard.

### Data correctness
- [ ] Serialized units and quantity lots are reported separately.
- [ ] Availability components are individually visible and use a documented formula.
- [ ] Every report states its date basis and as-of timestamp.
- [ ] Stale or failed data is not represented as current or zero.
- [ ] Cost fields identify source and approval status.
- [ ] Dashboard totals reconcile to authoritative records within the defined freshness window.

### Controls and audit
- [ ] Approval actions call server-side commands, not direct table updates.
- [ ] Separation-of-duties policy is enforced where configured.
- [ ] Sensitive fields are masked or omitted by default.
- [ ] Exports are logged and access-controlled.
- [ ] Dashboard views do not create a second inventory authority.

### Quality
- [ ] Role and location-scope tests pass.
- [ ] Report calculations are tested against deterministic fixtures.
- [ ] Large report behavior and timeouts are tested.
- [ ] Reconciliation and stale-data warnings are tested.
- [ ] Accessibility and responsive behavior are reviewed.

## 13. Proposed dashboard navigation

1. **Overview** — executive/store summary and exceptions.
2. **Stock** — SKU, unit, lot, location, condition, and lifecycle.
3. **Receiving** — expected receipts, receipt history, and discrepancies.
4. **Reservations** — active, expiring, committed, and released allocations.
5. **Transfers** — dispatch, in-transit, receipt, and variances.
6. **Counts & Reconciliation** — count plans, variances, and reconciliation runs.
7. **Exceptions** — holds, quarantine, identity conflicts, and incidents.
8. **Reports** — aging, movement, availability, supplier, and approved valuation.
9. **Administration** — report definitions, thresholds, and role-scoped settings, subject to approved permissions.

## 14. Completion boundary and next gate

This document is a design specification only. It does not create dashboard pages, charts, APIs, reporting tables, exports, permissions, or alerts. No tests or database inspections were run.

**Next gate:** Review the dashboard metrics, report definitions, and access boundaries. After the underlying Inventory Core services and authorization are implemented and verified, dashboard implementation can be broken into UI and reporting work items.
