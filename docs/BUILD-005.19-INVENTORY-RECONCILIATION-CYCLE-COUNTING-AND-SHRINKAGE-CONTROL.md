# Build 005.19 — Inventory Reconciliation, Cycle Counting, and Shrinkage Control

**Status:** Operations and control design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines physical counts, ledger reconciliation, variance investigation, shrinkage classification, approvals, and management reporting. No application code, database objects, count jobs, tests, or deployments are implemented.

## 1. Purpose

Establish a repeatable control system to compare MME's authoritative inventory records with physical stock and investigate differences without silently changing balances.

The system must distinguish a count observation from an approved inventory adjustment. A count never changes the inventory ledger merely because a user enters a number.

## 2. Control principles

1. Inventory Core's movement ledger remains the authoritative record of book quantity and location.
2. Physical observations are recorded separately from book balances.
3. Variances require investigation, evidence, reason classification, and approval under policy.
4. No employee may approve their own high-risk adjustment where separation of duties is required.
5. Serialized devices are reconciled individually; quantity-controlled goods are reconciled by SKU, lot, and location.
6. Open reservations, transfers, receipts, returns, holds, and sales must be considered during count cutoffs.
7. Count scope, cutoff time, count method, and reconciliation status must be visible.
8. Adjustments use compensating ledger movements; historical movements are never overwritten or deleted.
9. Suspected theft, fraud, or safety incidents are escalated through approved management/LP processes.
10. Reports distinguish confirmed actuals from estimates and unresolved observations.

## 3. Count program

Support the following count types:

- **Full physical inventory:** all in-scope stock at a location.
- **Cycle count:** scheduled subset by SKU, category, bin, value, risk, or velocity.
- **Spot count:** targeted count initiated by an exception or manager.
- **Blind count:** counter sees the count target but not the book quantity.
- **Recount:** independent second count after a variance.
- **Serialized-unit verification:** confirm each expected unit's physical presence and identity.
- **Location verification:** confirm stock is in the recorded bin/zone.
- **Event-driven count:** after transfer discrepancy, suspected loss, damage, or repeated transaction error.

Count policies should define frequency and coverage by risk and value. This document does not prescribe a statutory accounting or audit frequency.

## 4. Count planning and scope

Each count plan should capture:
- unique count ID and version;
- company, store, warehouse, zone, and bin scope;
- SKU/category/lot/unit filters;
- planned start and cutoff;
- count type and method;
- assigned counters and independent reviewers;
- count freeze or movement-control strategy;
- excluded items and documented reason;
- required evidence and approval thresholds;
- status, owner, and escalation deadline.

The plan must snapshot its scope. Later catalog or location changes must not silently rewrite the count definition.

## 5. Cutoff and movement control

Before counting:
1. Identify open receipts, transfers, reservations, orders, returns, and adjustments in the count scope.
2. Define a transaction cutoff and record its timestamp.
3. Pause or serialize affected movements where operationally feasible.
4. If work must continue, capture every in-scope movement during the count and reconcile it against the cutoff.
5. Clearly mark staged, reserved, quarantined, display, repair, and in-transit stock.
6. Ensure stock is counted once in the correct location and not double-counted in staging and storage.

A count must not proceed as if the location were static when concurrent movements are untracked.

## 6. Counting workflow

Proposed lifecycle:
1. Draft
2. Approved
3. Scheduled
4. In progress
5. Submitted
6. Variance review
7. Recount required (if applicable)
8. Approved for adjustment
9. Posted
10. Closed

A count may be cancelled only with a reason and audit record. Submitted observations must not be silently edited; corrections create a new version or superseding observation with attribution.

### 6.1 Count entry
- Scan or select the authorized location and SKU/unit/lot.
- Record observed quantity or serialized-unit presence.
- Capture counter, timestamp, method, and device/workstation reference.
- Record damaged, unidentified, misplaced, or inaccessible stock separately.
- Support blind counts where policy requires.
- Prevent duplicate submissions and flag repeated scans.

### 6.2 Recount
- Trigger by configured variance threshold, high-value item, serialized mismatch, or suspected control issue.
- Assign a different counter when separation of duties is required.
- Preserve first count and recount as separate evidence.
- Do not average conflicting counts automatically.

## 7. Variance classification

Every variance must have a reason category, notes, and evidence appropriate to risk.

Proposed categories:
- shortage / not found;
- overage / unexpected stock;
- wrong SKU or variant;
- wrong condition grade;
- wrong location/bin;
- unrecorded receipt;
- unrecorded transfer or transfer discrepancy;
- duplicate or erroneous transaction;
- incorrect unit of measure;
- return not processed or mis-dispositioned;
- damage, repair, or quarantine status mismatch;
- suspected theft or loss;
- identifier mismatch or duplicate serial/IMEI;
- count error or process failure;
- unknown / pending investigation.

Unknown must remain a valid temporary classification; it must not be forced into a convenient financial reason.

## 8. Investigation and evidence

Variance cases should include:
- count plan and observations;
- book quantity and ledger cutoff reference;
- relevant movement, receipt, transfer, order, and return references;
- location and custody history;
- item condition and identifier validation results;
- photographs or supporting documents where appropriate;
- employee statements or witness details only where lawfully collected and access-controlled;
- investigation owner, status, and due date;
- root cause and corrective/preventive action.

Evidence must be access-controlled, timestamped, and retained according to approved policy. Do not place full serial/IMEI values in general alerts.

## 9. Adjustment approval and posting

An approved adjustment must:
- reference the count and variance case;
- identify the affected SKU/unit/lot and location;
- state the approved quantity delta and reason;
- include approver and supporting evidence;
- enforce separation of duties where configured;
- use an idempotent command;
- create a compensating inventory ledger movement;
- preserve prior book balance and all historical movements;
- update projections only after authoritative commit.

The system must not:
- auto-adjust simply because a count differs;
- permit negative balances unless an explicitly approved policy allows a defined exception;
- delete or rewrite historical movements;
- post an adjustment with unresolved identity or location ambiguity;
- convert suspected theft into a routine shrinkage write-off without required review.

## 10. Shrinkage and loss controls

Classify confirmed losses separately from unexplained variance. Possible categories include:
- confirmed theft;
- suspected theft under investigation;
- damage;
- administrative/process error;
- supplier short shipment;
- transfer loss;
- return fraud or disposition error;
- unidentified shrinkage.

Track quantity and approved cost basis separately. Financial valuation and accounting treatment remain subject to the Finance authority and approved accounting policy. Do not treat retail price as inventory cost.

Escalate repeated losses by SKU, location, shift, workflow, and time period, while avoiding unsupported accusations against individuals.

## 11. Security and separation of duties

Proposed permission groups, mapped through Build 004:
- create and schedule count;
- perform count;
- submit count;
- view book quantities;
- view blind-count results after submission;
- investigate variance;
- approve adjustment;
- post adjustment;
- view restricted cost/valuation;
- close count and export evidence.

Controls:
- actor and location authorization are checked server-side;
- counters cannot alter book balances;
- high-risk adjustments require independent approval;
- privileged overrides require a reason and audit record;
- employee performance or disciplinary decisions must not be based solely on an automated variance alert.

Build 004 application-side session/actor enforcement remains unverified and is a production prerequisite.

## 12. Automation and alerts

Integrate with Build 005.12:
- overdue count assignment;
- high-value serialized mismatch;
- repeated location variance;
- transfer/receipt mismatch;
- repeated unexplained shortage;
- unapproved adjustment attempt;
- count cutoff movement conflict;
- unresolved case approaching deadline.

Automation may create tasks, reminders, and escalation cases. It must not automatically post stock adjustments or declare theft.

## 13. Reporting

Proposed dashboards:
- count completion and overdue counts;
- variance rate by location/category/SKU;
- confirmed shrinkage versus unresolved variance;
- adjustment volume and value by approved cost basis;
- repeat variance and root-cause trends;
- serialized-unit exception aging;
- recount frequency and resolution time;
- adjustment approval and segregation-of-duty exceptions;
- stock accuracy trend with method and cutoff disclosed.

Reports must identify whether amounts are actual, estimated, or pending approval.

## 14. Acceptance criteria

- [ ] Count scope and cutoff are versioned and auditable.
- [ ] Physical observations are separate from book balances.
- [ ] Serialized units and quantity lots have appropriate count methods.
- [ ] Concurrent movements are frozen or explicitly reconciled.
- [ ] Blind counts and independent recounts are supported.
- [ ] Every variance has a classification, owner, and evidence trail.
- [ ] Unresolved variance is not automatically treated as theft or confirmed shrinkage.
- [ ] Adjustments require policy-based approval and separation of duties.
- [ ] Approved adjustments create compensating ledger movements only.
- [ ] Duplicate submissions and concurrent adjustments are safely handled.
- [ ] Cost reporting uses approved cost basis, not retail price.
- [ ] Reports separate confirmed loss, unresolved variance, and estimates.
- [ ] Tests cover cutoff, duplicate scans, serialized mismatch, partial movement, approvals, and ledger invariants.

## 15. Completion boundary and next gate

This is a design specification only. It does not execute counts, alter balances, create adjustment records, or establish an accounting policy. No database inspection, migration, test, or deployment was performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve count frequency by risk class, cutoff/movement policy, recount thresholds, adjustment approval matrix, and evidence-retention policy before implementation.
