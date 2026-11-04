# Build 005.20 — Inventory Purchasing, Supplier Management, and Reorder Automation

**Status:** Procurement and replenishment design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines supplier records, purchasing workflows, purchase orders, replenishment recommendations, receiving handoff, and procurement controls. No application code, database objects, supplier connections, purchase orders, tests, or deployments are implemented.

## 1. Purpose

Give MME a controlled procurement process that connects inventory demand to supplier purchasing while preserving approval authority, cost lineage, and receiving verification.

Forecasts and reorder recommendations are decision support. They must not independently commit MME to a purchase or payment.

## 2. Ownership boundaries

- **Build 005 Inventory Core:** stock balances, SKU/location availability, reservations, receipts, inventory movements, and inventory cost lineage.
- **Build 005.15 Forecasting:** demand estimates, stockout risk, safety stock, and replenishment recommendations.
- **Build 005.16 Valuation:** approved landed-cost allocation and inventory valuation reporting.
- **Build 004 Identity:** authenticated actor, roles, and permissions.
- **Finance/Accounting authority:** budgets, vendor payment approval, accounting treatment, and financial-period controls.
- **Build 002 / purchasing interface:** order, payment, and operational integration where applicable.
- **Build 008:** warehouse receiving and put-away workflow ownership where assigned.

No build may duplicate another build's authoritative records without an explicit integration contract.

## 3. Supplier master record

Proposed supplier profile fields:
- stable supplier ID;
- legal/business name and trading name;
- supplier type and status;
- approved contact details;
- billing and shipping references;
- payment terms as approved by Finance;
- currency and tax documentation references;
- categories and products supplied;
- lead-time history and service metrics;
- return, warranty, and dispute terms;
- due-diligence and approval status;
- contract/document references;
- created/updated actor and audit history.

Supplier bank details, tax identifiers, credentials, and sensitive documents require restricted storage and access. Do not place secrets in general notes or logs.

## 4. Supplier qualification and status

Proposed lifecycle:
1. Prospect
2. Due diligence
3. Pending approval
4. Approved
5. Conditional
6. Suspended
7. Blocked
8. Archived

Controls:
- only approved suppliers may be used for ordinary purchase orders;
- conditional suppliers require explicit scope and approval;
- suspended or blocked suppliers cannot receive new orders;
- status changes require reason, actor, evidence, and audit;
- supplier risk review may consider authenticity, product quality, delivery performance, return handling, and commercial terms.

Do not claim supplier legitimacy based solely on a marketplace profile or a submitted document.

## 5. Replenishment recommendation engine

Inputs may include:
- sell-through and completed sales;
- current sellable stock by location;
- reservations and committed demand;
- confirmed inbound purchase orders;
- confirmed transfers and in-transit stock;
- stockout and backorder history;
- supplier lead-time distribution;
- seasonality and promotions;
- safety-stock policy;
- aging, condition, and markdown status;
- margin and cash/budget constraints supplied by Finance.

Recommendation outputs:
- SKU and proposed supplier;
- target location;
- current available and committed quantity;
- projected demand horizon;
- lead-time and safety-stock assumptions;
- recommended order quantity;
- estimated unit and landed cost, clearly labeled;
- stockout/excess risk;
- reason and confidence/quality indicators;
- approval requirement and expiry/recalculation time.

Forecast and supplier data must show source, freshness, and whether values are actual, estimated, or projected.

## 6. Reorder policies

Support configurable policies by SKU, category, supplier, and location:
- min/max;
- reorder point;
- days of supply;
- order-up-to target;
- safety stock;
- supplier minimum order quantity;
- case pack or order multiple;
- lead-time buffer;
- seasonal or event-specific policy.

Do not apply one global reorder rule to every product. High-value serialized electronics, low-cost accessories, refurbished goods, and one-off auction lots require different treatment.

Recommendations must account for condition and variant; new, used, refurbished, damaged, and display stock must not be treated as interchangeable.

## 7. Purchase request and approval lifecycle

Proposed lifecycle:
1. Draft recommendation or manual request
2. Submitted
3. Budget/availability review
4. Supplier and pricing review
5. Approval pending
6. Approved
7. Purchase order issued
8. Supplier acknowledged
9. Partially fulfilled
10. Received / closed
11. Cancelled or disputed

Purchase requests should capture:
- requester and department/location;
- SKU, description, condition, quantity, and unit of measure;
- requested-by date and business reason;
- preferred supplier and alternatives;
- quoted price, currency, freight, taxes, and fees;
- estimated landed cost with allocation assumptions;
- supporting quote/document links;
- budget reference and approval chain.

Approval thresholds, role separation, and budget limits are Finance/management decisions and are not set by this document.

## 8. Purchase order controls

An approved purchase order should have:
- unique PO number;
- supplier and ship-to location;
- approved line items and quantities;
- agreed prices, currency, terms, freight, and delivery estimates;
- version and amendment history;
- authorized approver(s);
- issue and supplier acknowledgement timestamps;
- cancellation/close reason where applicable.

Controls:
- no PO is issued before required approval;
- changes to quantity, supplier, price, or terms trigger reapproval according to policy;
- duplicate supplier submissions and duplicate PO creation are prevented;
- purchase orders cannot silently exceed approved amounts;
- a PO is not proof of payment or receipt;
- supplier acknowledgement is not proof of shipment.

## 9. Quotes and supplier comparisons

Support comparison of supplier offers using normalized landed-cost assumptions:
- item price;
- shipping/freight;
- taxes and duties where applicable;
- handling, auction, and platform fees;
- expected defect/return exposure where evidence supports an estimate;
- lead time and delivery reliability;
- warranty and return terms;
- minimum order and payment terms.

Keep quoted, estimated, and actual amounts separate. Do not choose the lowest sticker price automatically if quality, authenticity, freight, or risk materially differs.

For mixed pallets or lots, Build 005.16 cost allocation principles apply: allocate item-specific landed costs using an approved, defensible method rather than equally dividing unlike products by default.

## 10. Receiving and three-way matching

Receiving should compare:
1. approved purchase order;
2. supplier shipment/packing documentation;
3. physically received and inspected goods.

Differences include short shipment, over shipment, wrong item, wrong condition, damage, serial/IMEI mismatch, substituted goods, and missing documentation.

- Create inventory only through the authorized receiving workflow.
- Match each serialized unit or quantity lot to the correct PO line.
- Do not mark goods sellable before required inspection and disposition.
- Keep disputed or excess goods in an exception/quarantine state.
- Invoice matching and payment approval remain with Finance; receipt alone does not authorize payment.

## 11. Returns, disputes, and supplier performance

Track:
- return authorization and supplier RMA;
- defective/incorrect goods;
- shortages and overages;
- credits and replacement commitments;
- warranty claims;
- dispute owner and resolution;
- supplier response and delivery performance.

Supplier scorecards may include on-time delivery, fill rate, defect rate, discrepancy rate, return resolution time, and price variance. Scores must disclose sample size and measurement period; small samples should not imply certainty.

## 12. Automation and alerts

Integrate with Build 005.12 using versioned, idempotent workflows:
- reorder recommendation created or expired;
- stockout risk threshold crossed;
- supplier lead-time changed;
- PO awaiting approval or acknowledgement;
- delivery overdue;
- receiving variance or inspection failure;
- supplier suspended while open PO exists;
- quote or contract approaching expiry;
- purchase order amendment requiring reapproval.

Automation may prepare drafts, reminders, and review tasks. It must not autonomously approve a purchase, issue an unapproved PO, change supplier bank details, or initiate payment.

## 13. Permissions and audit

Proposed permission groups, mapped through Build 004:
- manage supplier profiles;
- view restricted supplier documents;
- create purchase requests;
- view forecast recommendations;
- compare supplier quotes;
- approve purchase requests;
- issue/amend/cancel purchase orders;
- receive against purchase orders;
- manage supplier disputes;
- view costs and budgets;
- export procurement records.

Audit supplier changes, quote revisions, approval decisions, PO issue/amendment/cancellation, receipt exceptions, and financial handoffs. Build 004 application-side actor/session enforcement remains unverified and is a production prerequisite.

## 14. Reporting

Proposed management views:
- open purchase requests and approval aging;
- open POs and expected inbound inventory;
- supplier on-time delivery and fill rate;
- purchase price and landed-cost variance;
- stockout risk and excess-stock exposure;
- supplier discrepancy, defect, and return trends;
- procurement spend by category, supplier, and location;
- forecast recommendation acceptance/rejection;
- inbound commitments versus actual receipts.

Reports must distinguish approved commitments, supplier-confirmed shipments, physically received stock, and forecast-only recommendations.

## 15. Acceptance criteria

- [ ] Supplier records have stable IDs, statuses, and audit history.
- [ ] Restricted supplier data is access-controlled.
- [ ] Replenishment recommendations disclose assumptions and data freshness.
- [ ] Policies support different product types and location needs.
- [ ] New/used/refurbished/display condition distinctions are preserved.
- [ ] Purchase requests and POs have versioned approval lifecycles.
- [ ] PO amendments trigger policy-based reapproval.
- [ ] Recommendations cannot autonomously create binding purchases.
- [ ] Receiving verifies PO, shipment, and physical goods.
- [ ] Discrepancies are quarantined or disputed rather than silently accepted.
- [ ] Finance retains authority over budget, invoice matching, and payment.
- [ ] Landed-cost allocations follow approved Build 005.16 rules.
- [ ] Supplier metrics disclose evidence, sample size, and time period.
- [ ] Tests cover duplicate POs, approval bypass, amendments, partial receipts, supplier suspension, and cost lineage.

## 16. Completion boundary and next gate

This is a design specification only. No supplier was added or verified, no purchase request or PO was created, no supplier account was connected, and no funds were committed. No database inspection, migration, test, or deployment was performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve supplier qualification requirements, procurement authority/thresholds, budget controls, reorder policy by product class, and receiving/invoice handoff before implementation.
