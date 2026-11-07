# Build 010.85 — Inventory Valuation, Cost of Goods Sold (COGS) & Profitability Tracking

**Status:** Additive implementation contract committed on an isolated feature branch. No live valuation engine, COGS posting, accounting integration, cost database, migration, or production deployment is claimed.

## 1. Audit findings

Repository searches on the Build 010.84 line did not locate verified inventory valuation, COGS, landed-cost, costing-method, or item-level profitability runtime components. Build 008 defines the required Acquisition/COGS and Accounting boundaries, cost provenance, variable landed-cost allocation, approval, and gross-profit calculations, but explicitly states that it is a specification and not proof of runtime implementation. Build 010.80 requires approved cost evidence and finance-owned invoice matching; Build 010.81 requires an authoritative vendor/finance master and prohibits duplicating financial records.

Do not invent cost, inventory, vendor, AP, or general-ledger tables or create a competing financial source of truth. Inspect deployed schemas, acquisition documents, receiving/PO records, canonical inventory units and ledger, Accounting valuation policy, approved price versions, AP provider, tax/fee treatment, currencies, and existing financial reporting before runtime work.

## 2. Objective

Provide traceable, finance-approved inventory cost and valuation visibility at item, batch, product, and location levels, and connect verified sale events to COGS and gross-profit reporting without conflating estimates, inventory value, revenue, payment settlement, or accounting postings.

## 3. Source-of-truth boundaries

| Domain | Authority | Contract |
|---|---|---|
| Product/model and item identity | Canonical Catalog / Inventory | Reference stable product and physical unit IDs |
| Purchase and acquisition evidence | Approved Acquisition/COGS | Preserve source documents and item/batch provenance |
| Vendor legal identity and invoice | Approved Vendor / Finance/AP master | Reference stable vendor and invoice IDs; no duplicate master |
| Receipt quantity and condition | Receiving + canonical Inventory ledger | Accepted receipt is evidence of custody, not invoice payment |
| Landed cost calculation and approval | Acquisition/COGS with Accounting policy | Consume approved versioned cost record |
| Inventory valuation method and accounting recognition | Accounting | Finance-owned policy; no independent inventory valuation override |
| Approved selling price and discount | CEO-authorized Pricing | Consume approved active price version |
| Sale and return event | POS / Order Management / authorized Returns | Recognize cost only at the approved accounting event |
| Payment and settlement | Payment provider / Finance | Payment state is not inferred from sale or COGS |
| General ledger / financial statements | Accounting system of record | Post through approved integration and reconcile |

Missing or unverified authorities are dependencies, not permission to create parallel ledgers.

## 4. Item-level cost provenance

Every cost record must link, where applicable, to:
- Stable physical inventory unit or quantity lot and product/version.
- Acquisition batch, auction lot, purchase order, receipt, vendor and invoice references.
- Direct item purchase cost and source evidence.
- Shared cost-pool components such as freight, buyer/auction fees, taxes, handling, insurance, and other approved costs.
- Currency, exchange-rate source and timestamp.
- Allocation method, method version, weights/basis, formula, rounding rule, residual, and reviewer approval.
- Effective time, status (proposed/approved/superseded/reversed), actor, and audit/correlation IDs.

Directly attributable costs should be assigned to the specific item where supported. Shared costs must use a finance-approved causal allocation basis (for example measured weight, volume, relative value, or another documented driver). Never default to equal per-item allocation for a mixed-value pallet. Preserve original inputs and calculations so results can be reproduced. AI may extract, classify, compare, and propose; it cannot approve or finalize cost.

## 5. Costing and valuation policy

Accounting must select and document the applicable valuation method by legal entity, inventory class, and jurisdiction (for example specific identification for serialized units, FIFO, or weighted average where permitted). This contract does not select an accounting policy.

For each valuation run, preserve:
- Policy ID/version and effective date.
- Included/excluded inventory statuses and locations.
- Cost layer or pool references and quantity basis.
- Currency, exchange rate, and valuation timestamp.
- Treatment of freight/fees, discounts, rebates, taxes, returns, damaged/quarantined stock, write-offs, and shrink.
- Rounding, residual, lower-of-cost/market or net-realizable-value treatment where applicable, and impairment rules.
- Reviewer, approval, source revision, calculation version, and reconciliation totals.

Never revalue historical transactions by silently changing an old cost record. Corrections are versioned and posted using approved accounting adjustment processes.

## 6. COGS recognition and sale integration

- COGS is recognized only at the accounting-approved sale/fulfillment event, not when an item is scanned, picked, reserved, quoted, or payment is merely authorized.
- The exact recognition trigger must be agreed by Accounting for shipping, pickup, delivery, partial fulfillment, deposits, split tender, and returns.
- Consume the appropriate approved cost layer/unit cost once per eligible sold quantity/unit.
- Use stable sale-line/unit identity and idempotency key to prevent duplicate COGS posting.
- Keep order state, sale completion, payment capture, settlement, fulfillment, revenue recognition, and COGS posting distinct.
- Voids and cancellations before recognition release eligible reservations; after recognition use approved reversal/return accounting events, never delete original postings.
- Partial shipments/pickups recognize only eligible quantities under the approved policy.
- A refund does not automatically restore inventory or reverse COGS; the Returns disposition and Accounting policy determine the inventory and cost treatment.
- Reconcile COGS events to POS/order lines, canonical inventory movements, and general-ledger postings.

## 7. Profitability metrics

Where inputs are approved and complete, calculate:
- Unit landed cost and inventory carrying value.
- Unit gross profit and gross margin.
- Sale-line gross profit after approved discounts.
- Product, category, brand, store, channel, and period profitability.
- Inventory aging, turnover, days on hand, sell-through, and gross-margin return on inventory where policy defines the calculation.
- Estimated gross-profit potential for unsold stock, explicitly labeled as an estimate.

Base formulas (subject to finance-approved inclusion rules):
- Gross profit = net recognized selling revenue − recognized COGS.
- Gross margin % = gross profit / net recognized selling revenue × 100, when the denominator is positive.

Define whether revenue is net of discounts, returns, taxes, shipping, payment fees, and other costs. Do not call gross profit “net profit.” Do not compare a current proposed price to a historical cost as realized profit. Every report includes currency, period/timezone, source, valuation date, cost/price version, freshness, and actual-versus-estimated label.

## 8. Financial controls and permissions

- Separate cost visibility from product/customer-facing permissions; public catalog and customer APIs must never expose cost, margin, supplier invoice, or acquisition evidence.
- Enforce role, legal-entity, location, and department scope server-side.
- Finance controls costing policy, valuation, COGS recognition, invoice matching, and GL posting permissions.
- CEO/delegated approvals apply only to defined business decisions; they do not bypass accounting policy or statutory controls.
- Segregate preparer, reviewer, approver, and poster for material cost/valuation changes.
- Service credentials remain server-side; RLS and audit protect cost records and financial events.
- Audit cost import, allocation, approval, valuation runs, sale/COGS events, reversals, exports, and manual overrides.
- Use decimal-safe monetary arithmetic and explicit ISO currency; never use floating-point arithmetic for money.

## 9. Exceptions and reconciliation

Create controlled cases for missing source cost, duplicate invoice, vendor/PO/receipt mismatch, unallocated residual, unsupported currency, exchange-rate gap, negative/zero price, cost layer shortage, partial fulfillment mismatch, duplicate COGS event, return/refund mismatch, damaged inventory, valuation variance, and GL posting failure.

Each case records expected/observed values, source references, amount/currency, owner, severity, evidence, aging, state, resolution reason, approval and history. Automation may detect, route, and retry idempotent postings; it may not approve financial adjustments or mark invoices paid.

Reconcile:
1. PO and vendor invoice to accepted receipt.
2. Receipt and acquisition cost to item/batch cost records.
3. Inventory units/quantities and valuation to ledger balances.
4. Eligible POS sale lines to COGS events.
5. COGS subledger to general-ledger postings.
6. Returns, refunds, write-offs, shrink, and approved adjustments to their accounting treatments.

## 10. Acceptance and regression tests

- Direct item costs retain exact source evidence and stable item linkage.
- Shared landed costs follow approved method/version and preserve weights, formula, currency, rounding, and residual.
- Mixed-value items are not allocated equal pallet costs unless an explicitly approved policy requires it.
- Proposed/AI-generated costs cannot be treated as approved or posted.
- Valuation runs are reproducible against recorded source revisions and policy versions.
- Restricted, incoming, in-transit, quarantined, damaged, and written-off inventory is treated according to approved valuation policy.
- Duplicate sale/fulfillment events cannot post COGS twice.
- Reservation, pick, quote, payment authorization, and unsettled payment do not independently trigger COGS.
- Partial fulfillment posts only eligible quantity under policy.
- Return/refund does not automatically restock or reverse COGS without authorized disposition/accounting event.
- Decimal/currency/rounding/zero-denominator cases produce deterministic results.
- Unauthorized roles cannot read costs, margins, invoices, or financial exports.
- Public/customer product APIs expose no cost or supplier data.
- GL posting failure remains visible and recoverable without falsely marking reconciliation complete.
- Regression tests preserve customer sign-in, employee sign-in, catalog, POS, warehouse, receiving, transfers, cycle counts, returns, and website stock behavior.

## 11. Runtime implementation gates

Do not mark Build 010.85 implemented or live until:
1. Canonical acquisition, vendor/AP, receiving, inventory, order/POS, pricing, identity, audit, and accounting/GL schemas and provider ownership are inspected.
2. Accounting approves valuation method, cost components, allocation hierarchy, currencies, recognition trigger, return treatment, rounding, and reconciliation policy.
3. Cost provenance and access classification are reviewed by finance/security.
4. Additive migrations and RLS policies are reviewed; no competing cost or GL master is introduced.
5. Cost allocation, valuation, COGS, reporting, and exception workflows are implemented against canonical authorities.
6. Sale/fulfillment/return events are integrated with durable idempotent posting and recovery.
7. Unit, integration, financial reconciliation, concurrency, privacy, and permission tests pass.
8. Staging valuation and COGS totals reconcile to approved source documents, inventory movements, POS lines, and GL records.
9. Customer/employee sign-in, catalog, POS, warehouse, receiving, transfers, counts, returns, and website regressions pass.
10. Finance, operations, security, and executive owners approve rollout; production deployment and post-deploy evidence record exact commit and environment.

**Release note:** This contract is not an accounting policy, cost approval, invoice payment, valuation adjustment, COGS posting, production migration, or deployment approval. No runtime financial feature or ledger posting is claimed by this document.
