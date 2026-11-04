# Build 005.28 — Inventory Supplier Intelligence, Vendor Scorecards, and Procurement Analytics

**Status:** Supplier intelligence and procurement analytics design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines supplier performance measurement and procurement decision support using MME acquisition, receiving, cost, quality, and fulfillment evidence. Build 005.20 remains the supplier and purchasing workflow authority. No vendor accounts were connected, supplier data imported, purchase orders created, or code/database changes, tests, or deployments performed.

## 1. Purpose

Help MME compare suppliers and acquisition sources using consistent, evidence-based measures of price, quality, delivery reliability, manifest accuracy, dispute resolution, and realized inventory recovery.

The scorecard is decision support. It must not automatically approve suppliers, place orders, negotiate commitments, or make payments.

## 2. Ownership boundaries

- **Build 005 Inventory Core:** actual receipts, item identity, condition, movements, and inventory availability.
- **Build 005.16:** approved landed-cost allocation and realized inventory profitability.
- **Build 005.20:** supplier records, qualification workflow, purchase requests, purchase orders, and receiving match.
- **Build 005.22:** bulk-lot, pallet, auction, and liquidation acquisition outcomes.
- **Build 005.23:** defect, warranty, repair, and refurbishment outcomes.
- **Build 005.19:** count variances and shrinkage evidence.
- **Finance:** payment, invoice, credit, and accounting authority.
- **Build 026:** enterprise analytics and reporting.

Supplier identity and procurement records must have one authoritative owner. Scorecards consume approved source records and do not create duplicate vendor masters.

## 3. Supplier profile and source classification

Support supplier/source classifications such as:
- manufacturer or authorized distributor;
- wholesale electronics supplier;
- liquidation or returns auction;
- pallet/bulk-lot source;
- refurbisher or repair provider;
- local business supplier;
- marketplace or broker.

A profile may include legal/business identity, verified contact channels, remittance details held in restricted systems, contract references, tax/compliance documents where applicable, product categories, locations, approved payment terms, and qualification status.

Clearly distinguish verified supplier information from user-entered, imported, or unverified claims. Restricted banking and tax data must not appear in ordinary inventory dashboards.

## 4. Scorecard dimensions

Potential dimensions include:

### Price and landed cost
- quoted unit price versus approved purchase price;
- freight and additional fees;
- final landed cost per eligible item;
- cost variance against quote or approved budget;
- total recovery and realized margin where sales are complete.

### Delivery performance
- on-time arrival against confirmed date;
- lead-time variance;
- partial and short shipments;
- shipment damage;
- delivery communication quality.

### Manifest and receiving accuracy
- expected versus actual quantity;
- model/SKU match rate;
- serial/identifier accuracy;
- condition and accessory accuracy;
- document completeness;
- discrepancy frequency and severity.

### Product quality
- defect rate by product category/model/condition;
- activation/account-lock issues where relevant;
- return and warranty claim rate;
- repair/refurbishment rate and cost;
- resale eligibility and recovery.

### Service and resolution
- response time;
- dispute resolution time;
- credit/return completion;
- completeness of corrective action;
- repeat issue rate.

Do not combine unrelated measures into a single opaque rating without showing the underlying components.

## 5. Evidence and metric definitions

Every scorecard measure must define:
- numerator and denominator;
- eligible transaction population;
- time window;
- product/category segmentation;
- treatment of incomplete or disputed cases;
- source record and timestamp;
- minimum sample size;
- confidence or reliability indicator.

Examples:
- **On-time rate:** eligible deliveries received by the confirmed due date divided by eligible deliveries with a confirmed due date.
- **Manifest accuracy:** accepted manifest lines matching verified receipt divided by manifest lines actually evaluated.
- **Defect rate:** units confirmed defective under the approved inspection policy divided by units inspected in the selected cohort.
- **Landed-cost variance:** actual approved landed cost compared with the approved purchase estimate using the same cost basis.

A missing observation is not a successful result. Small sample sizes must be labelled and must not produce misleading rankings.

## 6. Supplier comparison and ranking

Allow authorized comparisons by:
- product category and model family;
- new, used, refurbished, returns, or liquidation condition;
- acquisition channel;
- shipment size and lot type;
- location and delivery route;
- date range and sample size.

Provide weighted views only where management approves the weights and methodology. Always allow users to inspect raw dimensions and underlying evidence. Avoid ranking suppliers whose populations are not comparable.

## 7. Procurement intelligence

Potential recommendations:
- request a new quote;
- seek clarification on manifest or condition terms;
- split an order across qualified suppliers;
- reduce exposure to a source with recurring discrepancies;
- negotiate freight or payment terms;
- require pre-shipment manifest detail;
- inspect a higher-risk shipment more closely;
- pause new purchasing pending dispute resolution.

Recommendations must include evidence, assumptions, expected benefit, uncertainty, and the responsible approval authority. Purchase decisions continue through Build 005.20 and Finance controls.

## 8. Acquisition-source performance

For pallets, liquidation lots, and auction sources, measure:
- manifest completeness;
- expected versus actual unit count;
- proportion sellable after inspection;
- proportion repairable or parts-only;
- average approved landed cost by product class;
- time from receipt to sellable status;
- realized sales recovery;
- unsold/aged stock;
- defect and discrepancy rates;
- final realized gross profit and margin after reconciled sales.

Keep projected retail value, estimated recovery, pending bids, and completed sales separate. Do not treat advertised retail value as realized recovery.

## 9. Alerts and supplier review

Potential alerts:
- repeated manifest mismatch;
- rising defect or warranty rate;
- late delivery trend;
- unresolved credit or dispute;
- unusual cost variance;
- missing compliance or contract evidence;
- supplier profile change;
- supplier qualification expiry;
- concentration risk in a single source.

Alerts create review tasks. They must not automatically blacklist a supplier, cancel an order, or change payment terms.

## 10. Governance, conflicts, and audit

- Define who may create, verify, approve, suspend, and reactivate supplier profiles.
- Separate supplier setup from payment-detail changes and payment release.
- Record source and verification status for material supplier data.
- Audit score methodology, weight changes, exclusions, overrides, and approval decisions.
- Disclose conflicts of interest under MME policy.
- Restrict supplier contracts, pricing, and financial data by role.
- Preserve dispute evidence and approved retention rules.

## 11. Reporting

Proposed reports:
- supplier scorecard by category and period;
- acquisition-source profitability cohort;
- landed-cost variance;
- on-time delivery and lead-time trends;
- manifest and receiving accuracy;
- defect, return, warranty, and repair outcomes;
- dispute aging and credits outstanding;
- supplier concentration and category exposure;
- procurement recommendation outcomes.

Reports must show the last refresh time, data completeness, sample size, and whether figures are actual, estimated, or pending.

## 12. Acceptance criteria

- [ ] Supplier records have one authoritative owner.
- [ ] Verified and unverified supplier facts are clearly distinguished.
- [ ] Scorecard measures have transparent definitions and denominators.
- [ ] Small samples and incomplete cases are clearly labelled.
- [ ] Supplier comparisons use comparable cohorts.
- [ ] Landed cost follows Build 005.16 approved policy.
- [ ] Defect and warranty outcomes use verified inspection/claim evidence.
- [ ] Projected retail value is not represented as realized recovery.
- [ ] Recommendations require authorized human approval.
- [ ] Scorecards cannot create purchase orders or release payments.
- [ ] Restricted supplier and financial data are access-controlled.
- [ ] Methodology changes and overrides are auditable.
- [ ] Tests cover missing data, small samples, disputed receipts, and metric reproducibility.

## 13. Completion boundary and next gate

This is a design specification only. No supplier was verified or scored, no vendor system was connected, no purchase order or payment was created, and no external supplier data was imported. No code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve supplier classifications, scorecard metric definitions, sample-size rules, comparison cohorts, qualification evidence, review ownership, and procurement recommendation thresholds before implementation.
