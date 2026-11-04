# Build 005.7 — Implementation Sequence and Development Rollout Plan

**Status:** Planning document only  
**Branch:** `implementation/build-005-inventory-core`  
**Scope:** Ordered delivery plan for Build 005 Inventory Core. No application code, dependencies, database objects, migrations, tests, or deployments are changed by this document.

## 1. Objective

Turn the approved Build 005 architecture and service contracts into a controlled implementation sequence that minimizes data risk and avoids parallel, conflicting inventory authorities.

The rollout is additive and branch-based. Production remains untouched until separately reviewed and explicitly authorized.

## 2. Preconditions and current boundaries

Known project context:
- Build 004 identity schema exists in the Supabase project, but application-side session/actor integration has not been verified as complete.
- The previously supplied read-only discovery queries found ten identity tables in the inspected `public` scope and no matching inventory-related relation names in that scope. This was not an exhaustive inspection of all schemas or database objects.
- The user has asked to pause additional database inspections. No new inspections are included in this plan.
- Build 001 is an architecture/planning baseline and storefront shell/placeholder routes, not proof of persisted inventory or order workflows.
- Build 008 contains an inventory target specification; its functionality must be reconciled with Build 005 to avoid duplicate ownership.
- Build 005.5 migration design and 005.6 service/test contracts are proposals, not deployed implementations.

Do not start schema or application implementation until the relevant preconditions below are approved. The plan can be reviewed without further database inspection.

## 3. Delivery phases

### Phase 0 — Scope and ownership lock

**Goal:** Establish one source of truth for each domain.

Tasks:
1. Approve the Build 005.1 architecture, 005.4 blueprint, 005.5 migration proposal, and 005.6 API/test contract.
2. Confirm the Build 001, Build 005, Build 008, Build 017, POS, auction, shipping, pricing, and acquisition/COGS ownership boundaries.
3. Decide SKU/catalog ownership, store/location scope, serialized versus quantity-based inventory policy, cost allocation ownership, and reservation owner references.
4. Record decisions in versioned documentation before code changes.

Exit criteria:
- No duplicate inventory authority between builds.
- Unresolved decisions are explicitly assigned and not silently assumed.

### Phase 1 — Repository and environment readiness

**Goal:** Prepare a safe development path without touching production.

Tasks:
1. Confirm the active GitHub branch and repository state.
2. Review the actual application structure, existing data access patterns, environment-variable conventions, and package scripts when implementation is authorized.
3. Confirm the non-production Supabase project and migration-history strategy.
4. Verify the server-side Build 004 session and actor-resolution path; if incomplete, plan that prerequisite as a separately tracked task.
5. Confirm secrets remain in environment configuration and are never committed.
6. Establish backup, restore, and migration recovery expectations for the development environment.

Exit criteria:
- Development and production environments are unambiguously separated.
- Server-side identity and authorization dependencies have an approved implementation path.
- No secrets are present in source control.

### Phase 2 — Database preflight and migration readiness

**Goal:** Validate the live schema before writing executable migrations.

This phase is intentionally paused until the user authorizes further inspection.

When resumed:
1. Inspect all relevant schemas and migration history, not only the earlier `public` table-name query.
2. Check table/view/materialized-view/sequence/function/trigger/constraint/index/policy/grant/ownership state.
3. Reconcile every candidate Build 005.5 object against existing objects.
4. Verify RLS and least-privilege access design, including service-role boundaries and function execution rights.
5. Review data types, FK targets, deletion rules, identifier protection, and migration dependencies.
6. Produce a preflight report and proposed migration list for review.

Exit criteria:
- Object-name collisions and dependencies are resolved.
- Security and ownership decisions are documented.
- Migration plan is approved before any SQL is applied.

### Phase 3 — Foundation schema and security

**Goal:** Add the smallest safe inventory foundation.

Proposed order:
1. SKU and location references, with approved catalog and store scope.
2. Serialized units and quantity lots as separate models.
3. Identifier protection and uniqueness strategy.
4. Constraints and indexes.
5. RLS/grants/policies and server-only access boundary.
6. Migration verification and recovery rehearsal in non-production.

Exit criteria:
- Schema matches the approved design.
- Direct client access is restricted as designed.
- Migration verification passes in non-production.
- No inventory UI or external workflow is allowed to write around the service boundary.

### Phase 4 — Ledger, receiving, and inspection

**Goal:** Make inventory changes traceable from the first stock receipt.

Proposed order:
1. Append-only movement ledger and correction semantics.
2. Receipt header and receipt-line workflow.
3. Unit/lot creation linked to receipt evidence.
4. Inspection records and controlled lifecycle transitions.
5. Atomic transactions and idempotent receive/inspect commands.
6. Reconciliation checks for receipt quantities, stock records, and movements.

Exit criteria:
- Every received unit or quantity is traceable to a receipt and movement.
- Duplicate receiving requests do not duplicate stock.
- Invalid state transitions are rejected.
- Corrections preserve historical evidence.

### Phase 5 — Holds, reservations, and availability

**Goal:** Prevent double-selling and overselling.

Proposed order:
1. Holds and release controls.
2. Reservation headers and lines.
3. Concurrency-safe allocation for serialized units and quantity lots.
4. Reservation expiry and safe release processing.
5. Availability read service with freshness metadata.
6. Reconciliation between reservations, stock, and availability projection.

Exit criteria:
- Concurrent reservation tests demonstrate no duplicate unit allocation or quantity oversell.
- Replays are idempotent.
- Expired or released reservations return stock exactly once.
- Website and POS read the same authoritative availability result.

### Phase 6 — Transfers, adjustments, and reconciliation

**Goal:** Support controlled store operations.

Proposed order:
1. Location transfers with source/destination movement history.
2. Privileged adjustments with reason codes and evidence.
3. Compensating movements rather than destructive ledger edits.
4. Scheduled/on-demand reconciliation reports.
5. Alerting and discrepancy review workflow.

Exit criteria:
- Transfers balance across locations.
- Adjustments are permission-gated and auditable.
- Reconciliation identifies drift without silently rewriting history.

### Phase 7 — Application integration

**Goal:** Connect consumers through the approved service contract.

Integrate in this order:
1. Internal service and authorization layer.
2. Receiving and inventory administration.
3. POS SKU resolution, reservation, and sale commit.
4. Storefront availability and order reservation.
5. Auction allocation and commit.
6. Shipping/local pickup handoff.
7. Build 017 return dispositions.
8. Analytics and notifications through allowlisted outbox events.

Exit criteria:
- No consumer directly mutates inventory tables.
- Each integration uses the same service contract and idempotency behavior.
- Order/payment state remains owned by the relevant commerce/payment workflow.
- Inventory events do not leak protected identifiers or secrets.

### Phase 8 — Operational hardening and pilot

**Goal:** Validate real workflows in a controlled non-production pilot.

Tasks:
- Run the 005.6 unit, integration, security, concurrency, idempotency, event, failure, and reconciliation test matrix.
- Test receiving, inspection, hold/release, transfer, reservation, sale, return disposition, and pickup/shipping flows end to end.
- Exercise duplicate requests, timeouts, process restarts, and dependency outages.
- Validate audit trails, monitoring, alerts, backup/restore, and operator permissions.
- Train authorized staff and document exception procedures.

Exit criteria:
- All critical tests pass with recorded evidence.
- No unresolved critical/high security or data-integrity issue remains.
- Reconciliation and recovery procedures are demonstrated.
- Pilot acceptance is documented.

### Phase 9 — Production release gate

Production rollout is a separate approval decision.

Required:
1. Reviewed pull request and code review.
2. Verified non-production test evidence.
3. Approved migration plan, backup/recovery plan, and deployment window.
4. Explicit production authorization.
5. Staged rollout with monitoring and rollback/forward-recovery criteria.
6. Post-release reconciliation and sign-off.

No production migration, deployment, or live payment test is authorized by this plan.

## 4. Feature flags and rollout controls

Where the application supports feature flags, use server-controlled flags for:
- inventory read service;
- receiving and inspection;
- holds and reservations;
- POS commit;
- storefront availability;
- auction allocation;
- shipping/pickup transitions;
- event consumers.

Keep new mutation paths disabled until their database, authorization, idempotency, and reconciliation gates pass. Do not expose a client-controlled flag as an authorization mechanism.

## 5. Monitoring and operational signals

Proposed signals:
- receiving accepted/rejected counts and receipt reconciliation variance;
- available stock versus reserved/held/on-hand totals;
- reservation conflicts, expirations, and release failures;
- stale-version and idempotency-mismatch rates;
- movement ledger write failures;
- outbox age, retry count, and dead-letter volume;
- transfer imbalance and adjustment volume;
- reconciliation discrepancy count and age;
- unauthorized access attempts and protected-identifier access events.

Alerts must avoid exposing raw serial/IMEI, credentials, payment data, or unnecessary personal information.

## 6. Rollback and recovery principles

- Prefer additive, forward-compatible changes.
- Disable a feature flag before attempting to reverse an application release.
- Do not delete inventory history to simulate rollback.
- Use compensating movements for committed stock corrections.
- For schema changes, use a reviewed forward-recovery or restore plan; do not assume every migration is safely reversible.
- Reconcile stock, reservations, and movements after recovery.
- Preserve idempotency records so a retry cannot duplicate an already committed operation.

## 7. Delivery tracking

Track each phase with:
- owner and reviewer;
- linked GitHub issue/pull request;
- acceptance criteria;
- test evidence;
- migration identifier, if applicable;
- deployment environment;
- risk and recovery notes;
- explicit approval status.

A phase is not complete merely because its document or code exists. Completion requires evidence against its exit criteria.

## 8. Current status and next gate

Completed as documentation on the Build 005 branch:
- 005.1 architecture;
- 005.2 existing-schema crosswalk with the user's supplied read-only discovery results;
- 005.4 implementation blueprint;
- 005.5 proposed migration design;
- 005.6 API/service contract and test matrix;
- 005.7 implementation sequence and rollout plan.

Not established as implemented:
- Build 004 application-side session integration;
- Build 005 inventory schema, services, APIs, UI, tests, event consumers, or production deployment.

**Next gate:** Review and approve the Build 005 design package. Database preflight remains paused unless the user explicitly asks to resume inspections. After approval, the next work item is a scoped implementation issue list and acceptance checklist; it is not an automatic migration or production rollout.
