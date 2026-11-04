# Build 005.22 — Inventory Auctions, Liquidation, and Bulk-Lot Management

**Status:** Auction and liquidation inventory design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines how bulk lots, pallet acquisitions, auction listings, reserve outcomes, liquidation, and post-auction inventory movements connect to Inventory Core. It does not implement an auction platform, connect marketplaces, place bids, accept payments, or create database objects, tests, or deployments.

## 1. Purpose

Support MME's acquisition and resale of mixed pallets, bulk lots, individual units, and liquidation inventory while preserving item-level identity, landed cost, condition, stock availability, and sale history.

Auction and liquidation workflows must never create inventory merely because a listing exists or a bid is placed.

## 2. Ownership boundaries

- **Build 005 Inventory Core:** SKU/unit/lot identity, physical receipt, location, condition, stock ledger, holds, and availability.
- **Build 005.16:** acquisition cost lineage, landed-cost allocation, valuation, and profitability reporting.
- **Build 005.15:** demand and replenishment forecasts.
- **Pricing authority / Build 005.21:** approved fixed prices, floors, markdowns, and price versions.
- **Auction engine:** auction listing, bid rules, reserve, bid status, auction close, and unlock offer workflow.
- **Build 001 Website:** customer-facing listing, product details, and auction display.
- **Build 002 Orders/POS:** order commitment, payment authorization/capture, receipts, and fulfillment.
- **Build 017:** returns inspection and disposition.
- **Build 026:** auction, liquidation, and inventory performance analytics.

Each system must use documented contracts rather than maintaining conflicting copies of inventory or price authority.

## 3. Acquisition lot and pallet intake

A bulk acquisition record should capture:
- acquisition lot ID;
- supplier/auction source and source reference;
- purchase date and purchase price;
- buyer and approving actor;
- freight, taxes, fees, and other landed-cost inputs;
- expected manifest and source documents;
- estimated item count and categories;
- expected arrival date and receiving location;
- payment/settlement reference from the financial authority;
- actual receipt and discrepancy status.

Purchase approval and payment authority remain outside Inventory Core. A supplier manifest or marketplace invoice is evidence, not proof that every listed unit was physically received.

## 4. Manifest ingestion and research

Where a supplier CSV, spreadsheet, PDF, or document is supplied:
1. Preserve the original file and source metadata.
2. Parse rows into a reviewable staging record.
3. Normalize model, brand, description, quantity, condition, and identifiers where available.
4. Flag duplicates, missing fields, ambiguous models, and invalid identifiers.
5. Allow authorized review and correction before item creation.
6. Retain a mapping from each accepted item to the original source row/document.

External market/retail research may enrich a product description or provide price references. Research results must include source, retrieval time, match confidence, and estimated/actual designation. Similar model names must not be treated as exact matches without verification.

## 5. Itemization and cost allocation

A mixed pallet may contain televisions, laptops, tablets, phones, watches, accessories, and damaged or incomplete goods. The system must not divide pallet cost equally across unlike items by default.

- Identify and count actual received units.
- Assign SKU and serialized-unit identity where required.
- Record actual condition and completeness after inspection.
- Allocate freight and other shared costs using an approved, defensible method.
- Preserve direct item-specific costs separately from shared costs.
- Route unidentified or unallocatable costs for review.
- Keep preliminary estimates distinct from final approved landed costs.
- Reconcile total allocated cost to the acquisition lot's approved cost pool.

Build 005.16 governs the cost allocation method and valuation. No allocation formula is selected here.

## 6. Receiving, inspection, and disposition

Every received item must pass through the normal receiving and inspection workflow:
- match against expected manifest;
- record actual quantity;
- capture serial/IMEI for serialized goods through protected workflows;
- assess condition and accessories;
- identify damage, missing parts, activation/lock concerns, and duplicates;
- route exceptions to quarantine;
- determine whether the item is sellable, repairable, parts-only, return-to-supplier, or disposal candidate.

A manifest row or listing cannot bypass inspection. Unknown goods must not become sellable inventory.

## 7. Auction eligibility and inventory holds

Before a unit or lot can be listed:
- confirm physical receipt and eligible location;
- verify SKU/unit/lot identity and condition;
- confirm no conflicting reservation, order, hold, transfer, or active listing;
- verify approved pricing/reserve rules;
- place an auction-specific hold or allocation using Inventory Core's reservation/hold authority;
- record listing ID and hold reference.

Only eligible stock may be listed. A display/demo unit, quarantined item, or item already committed to another order cannot be offered as available stock.

## 8. Listing lifecycle and stock states

Proposed listing lifecycle:
1. Draft
2. Eligibility review
3. Approved
4. Scheduled
5. Live
6. Ended — reserve met
7. Ended — reserve not met
8. Cancelled
9. Settled / order committed
10. Fulfillment
11. Closed or disputed

The listing state and inventory state are separate. A live listing does not mean the item has sold. A winning bid does not become a completed sale until the auction and order/payment rules authorize the next transition.

## 9. Reserve not met and in-store price unlock

When reserve is not met:
- preserve the final bid and reserve outcome;
- do not mark the item sold;
- release or retain the auction hold according to the configured post-auction policy;
- offer the approved in-store price only after Pricing authority confirms its current price version;
- show the customer the actual eligibility, expiry, and fulfillment terms;
- do not imply that a bid guarantees the unlocked price or that stock remains available indefinitely.

Any unlock offer must be an explicit, auditable offer with eligibility and expiration rules. It must not silently bypass a price floor or existing reservation.

## 10. Auction close, winner, and settlement

At auction close:
- verify authoritative auction state and final bid;
- validate reserve outcome and bidder eligibility;
- create an order or settlement handoff using an idempotent command;
- apply payment authorization/capture only through the approved payment/order authority;
- commit inventory only at the defined order commitment point;
- release losing/expired holds safely;
- retain the complete bid, listing, price, and inventory event history.

A payment failure, disputed bid, or expired settlement window must follow an explicit recovery workflow. Do not remove inventory from stock solely because a client displays a winner banner.

## 11. Bulk-lot sale and partial allocation

Support both:
- selling a complete lot as one offer; and
- breaking down a received lot into individually sellable units or approved sub-lots.

The lot cannot be sold as a whole and simultaneously allocated to individual listings. Once split, preserve parent acquisition lot lineage and item-level cost allocations. Partial-lot sales must decrement only the authorized quantity and maintain traceability.

## 12. Liquidation and clearance

Liquidation candidates may be identified using:
- inventory age;
- low sell-through;
- excess stock;
- model obsolescence;
- repair economics;
- storage/carrying cost;
- condition and completeness;
- approved cash recovery targets.

Disposition options may include:
- fixed-price markdown;
- auction;
- bulk-lot sale;
- supplier return;
- repair/refurbishment;
- parts recovery;
- donation or disposal where authorized.

Recommendations are not approvals. Below-floor or unusual liquidation decisions require the pricing and management approval matrix.

## 13. Automation and exception handling

Integrate with Build 005.12:
- manifest parsing exception;
- expected-versus-received discrepancy;
- item not yet inspected;
- cost allocation unresolved;
- duplicate or conflicting listing;
- auction hold nearing expiry;
- listing ended without settlement;
- reserve-not-met unlock offer expiry;
- payment/order handoff failure;
- winning bid disputed;
- inventory and auction status mismatch;
- liquidation approval overdue.

Automation may create review tasks and reminders. It must not fabricate stock, approve a liquidation, capture payment, or silently release an unresolved disputed item.

## 14. Reporting

Proposed dashboards:
- acquisition lots by status and expected arrival;
- manifest versus actual received quantities;
- received, inspected, quarantined, and sellable units;
- estimated versus approved landed cost;
- auction listings and reserve outcomes;
- winning bids awaiting order/payment settlement;
- inventory held for active listings;
- reserve-not-met unlock conversion;
- liquidation recovery by approved cost basis;
- aging and sell-through by acquisition lot/category;
- supplier/source discrepancy and defect trends.

Keep bid amounts, gross proceeds, net revenue, cost, gross profit, and gross margin distinct. Reports must label estimates and pending settlements.

## 15. Security, audit, and permissions

Proposed permission groups, mapped through Build 004:
- upload and review acquisition manifests;
- create/edit acquisition lot staging records;
- inspect and disposition received goods;
- approve auction eligibility;
- create and approve listings;
- set/approve reserve and unlock offer rules;
- approve liquidation and below-floor disposition;
- view restricted acquisition cost and margin;
- resolve auction/inventory discrepancies;
- export acquisition and auction evidence.

Audit source document ingestion, row corrections, unit identity assignment, cost allocation approval, listing eligibility, holds, reserve outcomes, unlock offers, settlement handoffs, and liquidation decisions. Build 004 application-side actor/session enforcement remains unverified and is a production prerequisite.

## 16. Acceptance criteria

- [ ] Acquisition lots retain source documents and manifest lineage.
- [ ] Manifest parsing stages data for review before inventory creation.
- [ ] Actual received quantities are distinct from expected manifest quantities.
- [ ] Serialized items receive protected unit identity and identifier handling.
- [ ] Inspection is required before sellable status.
- [ ] Mixed-lot cost allocation follows approved Build 005.16 policy.
- [ ] Auction eligibility checks location, condition, reservations, and holds.
- [ ] Listing state is separate from inventory and order state.
- [ ] Reserve-not-met does not mark stock sold.
- [ ] In-store unlock offers use current authorized price and explicit expiry.
- [ ] Winning bids use idempotent order/payment handoffs.
- [ ] Bulk lots cannot be double-allocated as both whole lots and individual units.
- [ ] Liquidation requires policy-based approval and audit history.
- [ ] Reports distinguish estimates, bids, settled sales, and actual profit.
- [ ] Tests cover duplicate listings, partial lots, failed settlement, hold expiry, and concurrent allocation.

## 17. Completion boundary and next gate

This is a design specification only. No marketplace was connected, no pallet manifest was imported, no listing or bid was created, and no payment was attempted. No code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve acquisition intake fields, inspection/disposition rules, listing eligibility, reserve/unlock policy, settlement windows, and liquidation authority before implementation.
