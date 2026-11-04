# Build 005.16 — Inventory Valuation, Cost Intelligence, and Profitability Reporting

**Status:** Financial inventory design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines inventory cost lineage, valuation methods, margin analysis, reconciliation, and financial reporting boundaries. No accounting policy is selected or posted by this document. No code, database objects, integrations, journal entries, tests, or deployments are implemented.

## 1. Purpose and ownership

Give authorized MME decision-makers a reliable view of inventory investment, item-level cost, estimated retail value, realized gross profit, and inventory risk—without confusing operational estimates with accounting balances.

- Inventory Core owns quantities, stock states, movements, and locations.
- Acquisition/COGS owns acquisition evidence and approved landed-cost calculations.
- Pricing owns selling prices and markdown policy.
- Finance/accounting owns the approved valuation policy, financial close, and ledger postings.

## 2. Non-negotiable principles

1. Preserve actual purchase evidence and item-level cost lineage.
2. Never assume unlike products have equal cost because they came from one pallet.
3. Keep purchase cost, allocated landed cost, carrying value, retail price, sale proceeds, and gross profit distinct.
4. Label values as actual, estimated, projected, or accounting-approved.
5. Never silently rewrite historical cost when an allocation is corrected.
6. Restrict cost, margin, and supplier terms to authorized roles.
7. Reconcile inventory quantity and valuation independently.
8. Finance approval is required before formal financial posting or accounting treatment.

## 3. Financial measure definitions

| Measure | Meaning | Authority |
|---|---|---|
| Acquisition purchase cost | Amount paid or payable for goods | Acquisition evidence / Finance |
| Allocated landed cost | Approved item-level share of purchase and eligible inbound costs | Acquisition/COGS policy |
| Inventory quantity | Authoritative units/lots on hand by state/location | Inventory Core |
| Inventory carrying value | Quantity multiplied by approved unit cost under selected policy | Finance/accounting |
| Retail/list price | Intended selling price | Pricing |
| Estimated retail value | Planning estimate based on price assumptions | Pricing/Analytics |
| Sale proceeds | Confirmed sale amount under completed order/POS workflow | Order/POS |
| Gross profit | Net sales less approved cost basis and applicable adjustments | Finance/Analytics |
| Gross margin | Gross profit divided by net sales, when net sales are positive | Finance/Analytics |

Reports must identify basis, timestamp, and status. Retail value is not cash, revenue, or guaranteed realizable value.

## 4. Cost lineage

For every received item or quantity lot, preserve references to:
- supplier, auction, or acquisition source;
- purchase/pallet/lot reference and original invoice or auction evidence;
- receipt line and received quantity;
- item/SKU/unit association;
- eligible freight, tax, handling, refurbishment, and other cost components;
- allocation method and version;
- approved unit cost and effective date;
- correction/credit references;
- approving actor and audit reference.

Do not copy payment credentials or unnecessary personal data into cost records.

### 4.1 Mixed-lot allocation

Allocation must follow the approved accounting policy and available evidence. Candidate bases include:
- direct item-specific cost when known;
- relative standalone selling value;
- relative weight or volume for freight-only allocation;
- another documented method approved by Finance.

Choose the method for each relevant cost component and apply it consistently. Do not automatically divide total pallet cost equally across unlike TVs, tablets, laptops, phones, and accessories.

### 4.2 Estimated cost

When item-level cost is unknown, mark it estimated and preserve assumptions. Do not silently promote an estimate to actual. Require approved reconciliation when invoice or allocation evidence arrives.

## 5. Valuation policy boundary

Potential methods and treatments—such as FIFO, weighted average, specific identification, lower-of-cost-and-net-realizable-value assessments, and treatment of refurbishment or inbound costs—require selection by qualified accounting leadership based on MME's applicable accounting framework and facts.

This document does not select a method or assert that any method is legally required. Implementation must support the approved method, record effective dates and policy version, preserve prior-period results, provide controlled adjustment workflows, and prevent unapproved changes to closed-period valuation.

## 6. Inventory valuation views

### 6.1 Quantity and cost summary

By location, SKU, condition, and age, show:
- physical on-hand;
- sellable, reserved, held, and quarantined quantities;
- in-transit quantity separately;
- approved unit cost;
- estimated or approved carrying value;
- data freshness and reconciliation status.

### 6.2 Aging and risk

Use a documented aging date basis, such as receipt date or first-sellable date. Show units and carrying value by age, slow/no-sale indicators, condition and return patterns, and potential markdown/transfer recommendations.

An aging threshold creates a review recommendation, not an automatic write-down or disposal.

### 6.3 Retail and recovery comparison

Compare carrying cost with current retail/list price and approved expected selling-price assumptions. Label retail value as reference only; do not present it as guaranteed liquidation value or realized profit.

## 7. Profitability reporting

Compute profitability from completed and reconciled transactions, not listings or forecasts.

Potential dimensions include SKU/product family, condition grade, store/channel, sales period, promotion/markdown, return/refund outcome, and acquisition lot.

Reports should distinguish gross sales, discounts, refunds/returns, net sales, approved COGS, gross profit, and gross margin. If operating costs are included, define a separate contribution measure. Do not call gross profit net profit or mix projected sales with actual closed transactions.

## 8. Cost corrections and financial controls

A cost correction must:
1. reference original acquisition and receipt evidence;
2. identify affected units/lots and periods;
3. state reason and supporting documentation;
4. calculate the proposed delta using the approved method;
5. require authorized review/approval;
6. preserve the original cost record and create a traceable adjustment;
7. identify whether period reopening or journal adjustment is required.

Closed periods must not be silently recalculated. Finance determines accounting treatment and whether a journal entry is needed.

## 9. Reconciliation controls

Reconcile separate layers:
- physical quantity vs Inventory Core ledger;
- received quantity vs acquisition evidence;
- unit/lot cost vs approved allocation;
- inventory subledger valuation vs finance general ledger;
- completed sales/returns vs COGS;
- transfers and in-transit custody vs location valuation.

Every difference needs an owner, age, status, reason, and resolution evidence. Do not hide unresolved differences by netting them away.

## 10. Access and audit

- Store employees see only cost information required for their role.
- Acquisition staff manage evidence and proposed allocations within assigned scope.
- Finance approves valuation policy, period-end treatment, and financial adjustments.
- Executives receive summarized valuation/profitability views according to approved permissions.
- Supplier terms, cost exports, and margin detail require explicit permissions.
- Record access to sensitive cost exports and privileged changes.
- Never expose costs or margins through public storefront APIs, customer receipts, or untrusted analytics payloads.

## 11. Forecast and scenario separation

Build 005.15 forecast outputs remain projections. They may inform proposed purchasing budgets and inventory risk but must not be included in actual carrying value, revenue, COGS, or realized profit. Scenario analysis remains separate from official valuation and financial close outputs.

## 12. Acceptance criteria

- [ ] Each cost amount has source evidence, allocation method, status, and effective date.
- [ ] Mixed-lot products support item-specific or approved allocation methods.
- [ ] Actual and estimated costs are visibly distinguished.
- [ ] Retail value is not mislabeled as carrying value or cash.
- [ ] Approved valuation method and policy version are recorded.
- [ ] Historical cost corrections preserve original records.
- [ ] Closed-period controls prevent silent retrospective changes.
- [ ] Profitability uses completed, reconciled sales and approved COGS.
- [ ] Gross profit is not mislabeled as net profit.
- [ ] Quantity and financial valuation reconcile independently.
- [ ] Cost/margin access and exports are permission-scoped and audited.
- [ ] No financial posting occurs without approved Finance workflow.

## 13. Completion boundary and next gate

This document is a design specification only. It does not establish MME's accounting policy, calculate actual inventory valuation, connect accounting software, post journal entries, or change cost records. No code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Finance/accounting review of valuation method, landed-cost allocation policy, treatment of refurbishment/freight/tax, period-close controls, and reporting definitions before implementation.
