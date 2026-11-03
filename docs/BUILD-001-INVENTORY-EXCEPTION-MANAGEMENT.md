# Build 001 — Inventory Intelligence & Exception Management

**Status:** Proposed additive migration; not applied.

## Exception types
The exception queue supports low stock, unmatched scans, receiving variances, stocktake variances, inventory adjustments, damage reports, quarantine, stale inventory, serialized-unit mismatches, duplicate identifiers and manual review.

## Lifecycle
Exceptions are created with severity, product/location, source reference, summary and structured evidence. Active deduplication keys prevent repeated events from creating duplicate open alerts; repeat signals update the existing record and preserve a deduplication event. Managers can acknowledge, investigate, assign, resolve, dismiss and reopen records. Resolution requires a code and explanatory note.

## Management queue
Filters include location, status, severity and exception type. Queue results include SKU/title when applicable, source references, assignment, acknowledgement and resolution context. A separate event table retains the action history.

## Automation boundary
This migration provides the secure persistence and RPC contract. The trusted MME event processor must subscribe to stock, receiving, stocktake, serialized-unit and reorder events; evaluate configurable thresholds; and call the exception creation RPC. Notification delivery (in-app, email, SMS), scheduled stale-stock sweeps and rule administration UI are separate integrations and are not activated by this migration.

## Security
All tables and RPCs are service-role only. The trusted application server must authenticate the actor, enforce CEO/manager/employee permissions and scope locations before calls. Never expose service-role credentials to browser clients. Do not put full IMEI or other unnecessary personal data in exception details.