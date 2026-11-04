# Build 005.29 — Inventory Financial Controls, COGS Reconciliation, and Audit Reporting

**Status:** Financial-control and reconciliation design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines the inventory-side financial evidence, cost-of-goods-sold (COGS) reconciliation, valuation controls, and audit reporting needed to connect physical inventory activity with approved financial records. Finance/accounting systems remain authoritative for accounting policy, journal entries, periods, and financial statements. No accounting integration, posting, code, database changes, tests, or deployments are implemented.

## 1. Purpose

Ensure MME can trace inventory from acquisition through receipt, cost allocation, storage, transfer, sale, return, refurbishment, liquidation, and final disposition—without confusing operational stock quantities with accounting balances or projected retail value.

## 2. Authority boundaries

- **Build 005 Inventory Core:** physical quantities, unit/lot identity, location, movements, reservations, and custody.
- **Build 005.16:** cost lineage, approved landed-cost allocation, valuation inputs, and profitability definitions.
- **Build 005.20:** supplier, purchase request/order, and receiving match.
- **Build 005.21:** approved selling prices, markdowns, and margin controls.
- **Build 005.22:** auction, liquidation, and bulk-lot sale outcomes.
- **Build 005.23:** returns, warranty, repair, and refurbishment cost evidence.
- **Build 002:** completed sales, refunds, exchanges, and order records.
- **Finance/accounting:** chart of accounts, inventory accounting policy, valuation method, COGS recognition, journal entries, close, tax treatment, and financial statements.
- **Build 026:** management reporting and analytics.

Inventory Core supplies reconciled operational evidence. It does not independently determine accounting treatment or post financial entries.

## 3. Financial data classifications

Every amount must be classified as one of:
- quoted or planned;
- estimated;
- approved operational cost;
- actual supplier invoice/charge;
- allocated landed cost;
- approved inventory valuation;
- pending sale or settlement;
- completed transaction revenue;
- recognized COGS;
- expense or recovery;
- adjustment or write-off;
- forecast or scenario.

Display currency, effective date, source, approval state, and accounting period where relevant. Never combine estimates and actuals without clear labelling.

## 4. Cost lineage

Preserve a traceable chain from:
1. supplier quote and purchase approval;
2. purchase order and invoice;
3. freight, tax, fees, and other landed-cost evidence;
4. acquisition lot and receipt;
5. manifest line and received unit;
6. approved item-level cost allocation;
7. transfers, returns, repair, and refurbishment;
8. sale, liquidation, or final disposition.

Do not overwrite original acquisition facts when costs are corrected or added. Store correction history, approver, reason, effective date, and source evidence. Build 005.16 governs allocation methods; no costing method is selected here.

## 5. Inventory valuation controls

Finance must approve:
- valuation basis and costing method;
- treatment of freight and acquisition fees;
- treatment of refurbishment and repair costs;
- treatment of damaged, obsolete, or unsellable goods;
- reserve/impairment and write-down policy;
- treatment of returns and warranty recoveries;
- period-end cutoffs and adjustments.

Operational dashboards may show quantities and approved valuation snapshots, but must identify the valuation method, snapshot date, and source. Retail price, advertised market price, and projected recovery are not inventory carrying value.

## 6. COGS evidence and sale matching

For each completed sale:
- reference the order and sale line;
- identify the exact serialized unit or quantity lot consumed;
- reference the authoritative inventory movement/commit;
- capture the cost basis and valuation version used;
- distinguish completed sale from pending authorization, capture, or settlement;
- preserve discount, tax, fee, and revenue fields separately;
- route the financial evidence to Finance/accounting for recognition.

COGS must not be recognized solely because an item was placed in a cart, listed in an auction, bid upon, reserved, or shipped with only a label created. The recognition trigger is determined by Finance/accounting policy.

## 7. Returns, exchanges, and refunds

A return must link to the original sale and original cost basis. Keep these separate:
- physical receipt of returned goods;
- refund approval;
- refund payment status;
- condition inspection and disposition;
- inventory restock or quarantine movement;
- accounting reversal or recovery.

An exchange must link the outgoing and incoming units and the related financial adjustment. Do not assume every returned item is restockable or that every refund restores inventory value.

## 8. Transfers and location accounting

Transfers change custody/location and must not be treated as sales or new acquisitions. Record:
- source and destination;
- dispatch and receipt evidence;
- in-transit status;
- partial receipt and discrepancy;
- approved freight/handling cost if applicable.

Any accounting treatment for inter-location transfers, freight capitalization, or loss in transit belongs to Finance.

## 9. Reconciliation framework

Reconcile independent evidence sets:
- purchase orders versus supplier invoices and credits;
- expected manifests versus physical receipt;
- received quantities versus inventory ledger;
- approved cost allocations versus acquisition cost pool;
- inventory movements versus order sale lines;
- completed sales versus inventory commitment;
- returns/refunds versus physical return receipt and disposition;
- transfers dispatched versus destination receipts;
- inventory subledger snapshots versus Finance's general-ledger control account.

Each reconciliation must define period, cutoff, currency, scope, source systems, matching keys, tolerances, and responsible reviewer.

## 10. Variance and adjustment workflow

Classify variances:
- quantity or existence;
- cost or allocation;
- timing/cutoff;
- duplicate or missing transaction;
- return/refund mismatch;
- transfer discrepancy;
- valuation difference;
- currency or tax mismatch;
- integration or mapping failure.

Workflow:
1. detect and preserve the source records;
2. assign an owner;
3. investigate root cause;
4. document proposed correction;
5. obtain approval under Finance and operational authority matrices;
6. post correction in the authoritative owning system;
7. rerun reconciliation;
8. close with evidence.

No automatic inventory or financial adjustment is permitted from a reconciliation alert alone.

## 11. Period close and cutoff

Provide a close checklist for:
- unreceived purchase orders and goods in transit;
- receipts awaiting invoice match;
- unallocated acquisition costs;
- open transfers and unresolved discrepancies;
- active reservations and auction listings;
- completed sales awaiting financial handoff;
- returns/refunds awaiting physical or financial resolution;
- repairs and refurbishment costs awaiting classification;
- approved write-offs and liquidation dispositions.

The accounting period and cutoff rules must be configured by Finance. Late events must be handled using approved adjustment-period procedures, not by silently rewriting closed history.

## 12. Audit reporting

Proposed reports:
- inventory quantity and valuation snapshot by location/category;
- acquisition cost pool and allocation reconciliation;
- purchase order/invoice/receipt match;
- inventory-to-COGS bridge;
- completed sales with missing inventory or cost references;
- returns and refunds reconciliation;
- transfer-in-transit and loss exceptions;
- adjustments, write-offs, and approvals;
- stale, incomplete, or disputed financial evidence;
- period-close exception register.

Reports must preserve drill-down to source records and identify prepared-by, reviewed-by, generated-at, filters, and methodology version.

## 13. Security and separation of duties

- Restrict cost, margin, valuation, invoice, and accounting exports by role.
- Separate supplier setup, invoice approval, payment release, stock adjustment, and reconciliation approval.
- Require independent approval for material write-offs and closed-period corrections.
- Protect financial exports and audit evidence.
- Log access, export, overrides, corrections, and approval decisions.
- Apply retention and legal-hold rules from Build 005.14.
- Build 004 application-side session/actor enforcement remains unverified and is a production prerequisite.

## 14. Acceptance criteria

- [ ] Operational inventory facts are distinct from accounting balances.
- [ ] Finance owns costing policy, valuation, COGS recognition, and journal posting.
- [ ] Cost lineage links acquisition evidence to received units and completed dispositions.
- [ ] Estimates, actuals, pending settlements, and recognized amounts are distinct.
- [ ] Completed sale lines link to inventory commitment and approved cost basis.
- [ ] Returns and exchanges preserve original sale and cost lineage.
- [ ] Transfers are not treated as sales or new acquisitions.
- [ ] Reconciliation covers purchases, receipts, allocations, sales, returns, transfers, and ledger snapshots.
- [ ] Variances require investigation and authorized correction.
- [ ] Closed-period history is not silently rewritten.
- [ ] Reports provide source-level drill-down and review evidence.
- [ ] Financial data exports and approval actions are access-controlled.
- [ ] Tests cover duplicate postings, cutoff errors, missing cost references, and return mismatches.

## 15. Completion boundary and next gate

This is a design specification only. No financial system was connected, no journal entry or COGS posting was created, and no accounting policy was selected. No code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Finance approval is required for valuation method, COGS recognition trigger, capitalization/expense rules, close calendar, reconciliation tolerances, adjustment materiality, and approval matrix before implementation.
