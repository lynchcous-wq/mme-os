# Build 005.26 — Inventory Security, Loss Prevention, and Fraud Detection

**Status:** Security and loss-prevention design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines inventory-specific safeguards for theft, diversion, fraudulent transactions, unauthorized adjustments, identifier misuse, and suspicious activity. This document complements the broader MME loss-prevention program; it does not connect cameras, alarms, payment systems, or external fraud services and does not implement code, database changes, tests, or deployments.

## 1. Purpose

Protect MME inventory throughout acquisition, receiving, storage, display, transfer, sale, return, repair, auction, and disposal. Detect suspicious patterns while preserving employee fairness, customer privacy, evidence integrity, and separation of duties.

## 2. Authority boundaries

- **Build 005 Inventory Core:** physical inventory identity, custody, locations, movements, holds, reservations, and availability.
- **Build 004 Identity:** authenticated actor, role, permission, and location scope.
- **Build 002 Orders/POS:** sales, payment status, refunds, voids, and transaction records.
- **Build 017 Returns:** return authorization, inspection, and disposition workflow.
- **Build 005.17:** transfers and warehouse custody.
- **Build 005.19:** counts, variances, and shrinkage investigation.
- **Build 005.22:** auction and liquidation listing/settlement lifecycle.
- **Build 005.23:** warranty, repair, and refurbishment.
- **Loss-prevention/security operations:** incident response, evidence custody, camera/alarm operations, and case management.
- **Build 026:** authorized risk and loss-prevention reporting.

Inventory risk signals are indicators for review, not proof of misconduct.

## 3. Threat model

Address risks including:
- unauthorized stock adjustments or write-offs;
- false receiving or inflated received quantities;
- theft or diversion during transfer, picking, or delivery;
- duplicate or substituted serial/IMEI identifiers;
- unauthorized access to restricted stockrooms;
- collusion or manipulation involving counts, returns, refunds, or voids;
- auction shill bidding or listing/hold manipulation;
- inventory reserved or sold beyond available quantity;
- fraudulent supplier manifests or altered acquisition documents;
- tampering with audit records or evidence;
- exposure of customer or device identifiers;
- misuse of employee credentials or shared accounts.

## 4. Preventive controls

- Require authenticated individual accounts; prohibit shared operator credentials.
- Apply least privilege by role, location, and task.
- Separate request, approval, and execution for high-risk adjustments and write-offs.
- Require reason codes and supporting evidence for corrections.
- Use server-side authorization for all inventory-changing commands.
- Enforce atomic reservations and unique serialized-unit allocation.
- Restrict access to receiving, quarantine, high-value stock, and secure storage locations.
- Record custody handoffs for controlled transfers and deliveries.
- Require count reconciliation and independent approval for material variances.
- Use tamper-evident audit and event records with restricted administrative access.
- Mask serial/IMEI and customer details in ordinary views and notifications.

## 5. Risk signals and anomaly detection

Potential signals include:
- repeated adjustments by the same actor or location;
- unusual adjustment timing or value;
- receiving quantities consistently exceeding manifests;
- repeated serial/IMEI mismatch or duplicate scans;
- inventory movement without expected dispatch/receipt evidence;
- high-value items repeatedly missing from counts;
- repeated return/refund/void patterns outside normal baselines;
- unusual reservation creation/release activity;
- multiple accounts or devices associated with suspicious auction activity, where lawful and proportionate;
- access attempts outside assigned location or role;
- repeated failed access to restricted inventory;
- unexplained differences between POS sales and inventory movements.

Each signal should include the underlying records, time window, baseline, confidence/evidence strength, and known limitations. Avoid demographic or other sensitive-trait inference.

## 6. Risk scoring and review

Use configurable risk tiers only after management and Legal/Privacy review:
- informational: monitor or trend;
- review: create an operational review task;
- elevated: supervisor investigation;
- critical: urgent security response under approved incident policy.

Risk scores must not automatically establish guilt, impose discipline, terminate access, or accuse a person. Human reviewers must evaluate context and preserve the ability to correct false positives.

## 7. Inventory custody and high-risk workflows

### Receiving
- Match expected manifest, purchase approval, and actual physical receipt.
- Record discrepancies and evidence before accepting variance.
- Use independent review for defined high-value or unusual receipts.

### Transfers
- Record dispatching and receiving custodians.
- Use sealed/container references where appropriate.
- Require destination confirmation and discrepancy investigation.

### Picking and fulfillment
- Verify order, SKU, condition, and serial/IMEI where required.
- Record picker/packer handoffs and shipment/pickup confirmation.
- Do not mark an item fulfilled solely because a label was created.

### Returns and repairs
- Link returned unit to original transaction and authorization.
- Preserve condition evidence and custody.
- Restrict write-off, parts removal, and resale disposition to approved roles.

### Auctions and liquidation
- Verify listing eligibility and active inventory hold.
- Audit reserve and unlock-price changes.
- Reconcile winning bid, order, payment, and physical inventory.
- Monitor suspicious bidding patterns without exposing bidder personal data to unauthorized users.

## 8. Incident and evidence workflow

Proposed case lifecycle:
1. Signal generated
2. Triage
3. Case opened
4. Evidence preserved
5. Investigation assigned
6. Findings reviewed
7. Corrective action approved
8. Resolution recorded
9. Case closed or referred

Evidence records should include source, capture time, custodian, access history, integrity metadata where supported, and relationship to inventory/order/employee records. Preserve originals; corrections and annotations must be additive.

Do not use automated facial recognition or infer identity from camera imagery as part of this design. Any camera or alarm integration requires separate privacy, legal, security, and vendor review.

## 9. Privacy and employee safeguards

- Collect only data necessary for a defined security purpose.
- Limit monitoring to authorized business systems, locations, and disclosed policies.
- Restrict case details to authorized investigators and decision-makers.
- Separate operational risk signals from HR disciplinary decisions.
- Provide documented human review and correction paths.
- Apply retention schedules, legal holds, and export controls.
- Avoid unnecessary collection of personal device, location, or biometric data.
- Do not expose allegations or investigation status in ordinary employee dashboards.

This design is not legal advice or a determination that any particular monitoring practice is lawful.

## 10. Response and containment

Possible approved responses:
- create a count or recount task;
- place a specific unit in a temporary review hold;
- restrict a listing pending verification;
- require supervisor review of an adjustment;
- preserve relevant records;
- escalate a security incident.

Any hold or restriction must identify its scope, reason, approver, start time, review deadline, and release authority. Do not freeze unrelated inventory or customer access based only on an unverified signal.

Emergency actions must follow an approved incident policy and be logged for prompt review.

## 11. Reporting and oversight

Proposed reporting:
- shrinkage and variance by category/location/time;
- inventory loss by lifecycle stage;
- high-risk adjustments and write-offs;
- receiving and transfer discrepancy trends;
- serialized identifier exceptions;
- restricted-location access events;
- return/refund/void correlation indicators;
- auction and liquidation exceptions;
- incident aging, outcomes, and false-positive rates;
- control completion and overdue reviews.

Reports must distinguish confirmed loss, unresolved discrepancy, suspected activity, and estimated exposure.

## 12. Security operations and audit

Audit:
- privileged access and permission changes;
- stock adjustments, holds, releases, and write-offs;
- receiving and transfer custody;
- serial/IMEI access and correction;
- count overrides and variance approvals;
- auction reserve/unlock changes;
- evidence access, export, and disposition;
- risk-rule/model version changes;
- case assignment, review, and closure.

Protect audit storage from ordinary application-user modification. Define backup, recovery, incident escalation, and periodic access review. Build 004 application-side actor/session enforcement remains unverified and is a prerequisite for production controls.

## 13. Acceptance criteria

- [ ] Inventory-changing commands enforce server-side identity and permission checks.
- [ ] High-risk actions use separation of duties and evidence.
- [ ] Serialized units cannot be duplicated or silently substituted.
- [ ] Receiving, transfer, picking, return, and repair custody is traceable.
- [ ] Risk signals show evidence and limitations.
- [ ] Risk scoring does not automatically accuse or discipline an individual.
- [ ] Case evidence has access history and retention controls.
- [ ] Sensitive customer and device identifiers are masked by default.
- [ ] Holds are scoped, time-bounded, reviewable, and releasable by authorized roles.
- [ ] Confirmed loss is distinguished from suspected activity and unresolved variance.
- [ ] Camera/alarm and external fraud integrations require separate approval.
- [ ] Tests cover unauthorized adjustments, audit tampering attempts, duplicate identifiers, and false-positive review.

## 14. Completion boundary and next gate

This is a design specification only. No monitoring, camera, alarm, fraud, or external security service was connected. No incident was opened, no inventory was held or adjusted, and no employee/customer risk determination was made. No code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve risk signal definitions, materiality thresholds, separation-of-duties matrix, case access rules, retention schedule, and incident response authority before implementation.
