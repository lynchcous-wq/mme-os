# Build 005.23 — Inventory Warranty, Returns, and Refurbishment Lifecycle Integration

**Status:** Inventory lifecycle integration design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines how warranty claims, customer returns, inspections, repairs, refurbishment, and resale disposition connect to Inventory Core. Build 017 remains the returns/refunds authority. No application code, database objects, warranty-provider connections, repair integrations, tests, or deployments are implemented.

## 1. Purpose

Maintain accurate inventory identity, condition, location, availability, and cost lineage when electronics are returned, inspected, repaired, refurbished, exchanged, or processed under warranty.

A returned item is not automatically sellable. Every physical unit must follow an authorized disposition workflow before its inventory state changes.

## 2. Ownership boundaries

- **Build 005 Inventory Core:** authoritative unit/SKU/lot identity, location, holds, movements, availability, and cost lineage.
- **Build 017 Returns & Refunds:** return authorization, eligibility, refund/exchange decision, condition assessment workflow, and return case.
- **Warranty service authority:** warranty terms, coverage dates, claim submission, provider decisions, and claim status.
- **Repair/service workflow:** diagnostic work, parts, labor, repair evidence, and technician completion.
- **Build 005.16:** approved refurbishment cost and inventory valuation treatment.
- **Pricing authority / Build 005.21:** resale price and margin controls after disposition.
- **Build 002 Orders/POS:** original transaction, exchange, refund, and payment records.
- **Build 004 Identity:** actor, role, permission, and location authority.
- **Build 026 Analytics:** returns, warranty, repair, recovery, and inventory performance reporting.

No integration may create a duplicate source of truth for a return, refund, warranty claim, or inventory balance.

## 3. Physical unit continuity

For serialized electronics:
- retain the same internal inventory unit ID throughout the unit's lifecycle;
- preserve serial/IMEI associations under protected access controls;
- record custody and location at each handoff;
- preserve original sale, receipt, acquisition lot, and cost lineage;
- record any authorized identifier correction with evidence and audit history;
- never reuse an inventory unit ID for a different physical device.

For quantity-controlled goods, track the returned quantity against the correct SKU/lot and preserve unit-of-measure rules.

## 4. Return intake handoff

When Build 017 authorizes a return:
1. Resolve the original order/sale and return authorization.
2. Identify the exact unit or quantity being returned.
3. Record receiving employee, location, timestamp, and custody handoff.
4. Place the returned goods into a non-sellable return/inspection state.
5. Link photographs, customer-provided information, and required evidence through the protected return case.
6. Confirm the physical receipt independently from refund or exchange settlement.

A refund approval or payment reversal does not prove that the item was physically received. Physical receipt does not itself authorize a refund.

## 5. Inspection and condition reassessment

Inspection should record, where applicable:
- exterior and screen condition;
- display, touch, buttons, ports, cameras, speakers, and microphones;
- battery health or diagnostic result where supported;
- power, charging, and connectivity;
- activation lock, account lock, or device-management status where lawfully and technically verifiable;
- accessories, packaging, and missing components;
- serial/IMEI consistency;
- evidence images and diagnostic references;
- inspector, time, location, and checklist version.

Results must distinguish verified test outcomes, customer statements, visual observations, and unknown/unavailable tests. Never mark a feature as passed when it was not tested.

## 6. Disposition workflow

Proposed disposition options:
- return to sellable stock at verified condition;
- refurbish/repair;
- parts-only inventory;
- supplier/manufacturer warranty claim;
- return to supplier;
- quarantine pending investigation;
- damaged/non-recoverable;
- approved disposal or other controlled write-off.

Disposition lifecycle:
1. Awaiting inspection
2. Inspection in progress
3. Inspection submitted
4. Review required
5. Disposition approved
6. Repair/refurbishment or other authorized path
7. Quality verification
8. Inventory state updated
9. Closed

The item remains unavailable for sale until the authorized workflow confirms eligibility and posts the required inventory movement.

## 7. Repair and refurbishment controls

A repair/refurbishment work order should reference:
- inventory unit or lot;
- return/warranty case;
- reported issue and diagnostic findings;
- approved work scope;
- assigned technician;
- parts used and their inventory references;
- labor and external service cost;
- repair start/completion timestamps;
- before/after condition and evidence;
- quality-control reviewer and result.

Controls:
- reserve parts before use through Inventory Core;
- issue parts through authorized inventory movements;
- do not treat planned parts as consumed until the usage transaction is confirmed;
- retain removed/replaced component traceability where required;
- record failed, incomplete, or abandoned repairs;
- require independent quality verification for configured high-risk product classes.

## 8. Refurbished grading and resale eligibility

A refurbished or used grade must be assigned only through an approved condition policy. Grade definitions should be consistent, versioned, and visible to authorized sales channels.

Resale eligibility requires:
- completed inspection and required diagnostics;
- resolved activation/account locks where relevant;
- verified identifier and ownership/return chain;
- complete accessories disclosure;
- approved warranty/return terms;
- approved condition grade;
- current pricing authorization;
- valid inventory location and sellable status.

The website must accurately disclose condition and included accessories. Do not represent refurbished stock as new or imply manufacturer certification without evidence.

## 9. Warranty claim lifecycle

Proposed claim states:
1. Draft
2. Evidence collection
3. Submitted
4. Provider review
5. Approved / denied / more information required
6. Repair / replacement / credit pending
7. Resolved
8. Closed or disputed

Record provider, coverage reference, claim number, submission date, response, decision, and settlement/replacement evidence.

Warranty coverage must be derived from the applicable transaction, supplier, manufacturer, or MME warranty terms. Do not infer coverage solely from a product's brand or purchase date.

A warranty replacement device is a new physical unit identity. Preserve the relationship between the original and replacement units without merging their identities.

## 10. Cost and financial lineage

Track separately:
- original acquisition/landed cost;
- repair parts cost;
- internal labor cost where approved;
- external service cost;
- warranty credit or supplier recovery;
- refurbishment cost;
- approved post-refurbishment valuation;
- realized sale revenue and gross profit.

Build 005.16 and Finance determine cost capitalization, expense, recovery, and valuation treatment. This build does not set accounting policy.

Do not overwrite original acquisition cost when repair costs are added. Maintain a traceable cost history and distinguish estimated from actual amounts.

## 11. Exchanges and replacement units

For exchanges:
- link the outgoing replacement unit to the original order and return case;
- validate availability and reserve the replacement through Inventory Core;
- preserve separate identities for returned and replacement units;
- coordinate exchange order and payment adjustments through Build 002;
- release the replacement reservation only under an authorized cancellation/expiry path;
- reconcile both physical movements and financial settlement.

A customer exchange must not silently substitute a different SKU, condition, or value.

## 12. Automation and alerts

Integrate with Build 005.12:
- return received but not inspected;
- inspection overdue;
- serialized identifier mismatch;
- item marked sellable without required quality verification;
- repair parts not reconciled;
- warranty claim response overdue;
- warranty replacement awaiting receipt;
- refurbishment cost incomplete;
- returned item still reserved/listed;
- repeated defect pattern by SKU, supplier, or model.

Automation may create tasks and escalation cases. It must not independently approve refunds, declare warranty coverage, mark an unverified item sellable, or dispose of inventory.

## 13. Security and audit

Proposed permissions, mapped through Build 004:
- receive returned inventory;
- view return and warranty cases;
- inspect serialized devices;
- view full serial/IMEI for authorized tasks;
- approve disposition;
- create and complete repair work orders;
- issue repair parts;
- approve quality verification;
- submit/resolve warranty claims;
- approve write-off or disposal;
- view restricted cost and recovery information.

Audit custody handoffs, inspection results, identifier access/corrections, parts usage, disposition approvals, warranty decisions, cost changes, and inventory movements.

Customer personal data and device identifiers must be masked from general inventory views and alerts. Build 004 application-side session/actor enforcement remains unverified and is a production prerequisite.

## 14. Reporting

Proposed reports:
- return volume and disposition by SKU/model/condition;
- return-to-inspection and inspection-to-disposition time;
- defect and repeat-failure rate;
- warranty claim approval and recovery rate;
- repair success, cost, and turnaround;
- refurbishment yield and resale recovery;
- parts usage and variance;
- returned stock awaiting disposition;
- items incorrectly or prematurely marked sellable;
- supplier/manufacturer defect trends.

Separate actual recovery and cost from estimates and pending claims. Restrict customer, identifier, and cost detail by role.

## 15. Acceptance criteria

- [ ] Return authorization and refund authority remain with Build 017 / order-payment authority.
- [ ] Physical receipt is distinct from refund settlement.
- [ ] Serialized unit identity and original acquisition lineage are preserved.
- [ ] Returned items enter a non-sellable state pending required inspection.
- [ ] Inspection records verified tests separately from unknown or untested items.
- [ ] Disposition requires authorized approval and appropriate evidence.
- [ ] Repair parts are reserved and issued through Inventory Core.
- [ ] Refurbishment grade and resale eligibility follow versioned policy.
- [ ] Warranty coverage is based on documented terms and provider decisions.
- [ ] Replacement devices receive distinct unit identities.
- [ ] Repair and refurbishment costs do not overwrite original acquisition cost.
- [ ] Exchanges reconcile both inventory movements and financial settlement.
- [ ] Automation cannot independently approve refunds, warranty coverage, or write-offs.
- [ ] Tests cover duplicate return intake, identifier mismatch, parts usage, warranty replacement, and premature resale.

## 16. Completion boundary and next gate

This is a design specification only. No return, refund, warranty claim, repair, replacement, or inventory disposition was processed. No provider was connected, and no code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve condition-grade definitions, inspection checklists by product class, refurbishment quality standards, warranty evidence requirements, repair cost treatment, and disposition approval thresholds before implementation.
