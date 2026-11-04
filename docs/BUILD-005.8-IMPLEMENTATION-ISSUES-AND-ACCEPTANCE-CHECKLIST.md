# Build 005.8 — Implementation Issues and Acceptance Checklist

**Status:** Planning backlog only  
**Branch:** `implementation/build-005-inventory-core`  
**Scope:** Actionable work breakdown for Build 005 Inventory Core. No application code, dependencies, SQL, database objects, tests, or deployments are changed by this document.

## 1. Purpose and rules

Convert the Build 005 design package into reviewable implementation work items. This backlog is not evidence that any feature has been implemented.

- Preserve Build 004 identity and permission ownership.
- Keep Inventory Core the sole authority for stock state, movement, reservations, and availability.
- Preserve boundaries with Catalog, Acquisition/COGS, Pricing, Orders/POS, Auction, Returns (Build 017), Shipping/Pickup, and Analytics.
- All mutations use trusted server-side services; no client-side direct stock writes.
- Use additive changes, feature branches, pull-request review, and recorded test evidence.
- Do not commit secrets, raw serial/IMEI values, payment data, or unnecessary personal data.
- Database preflight remains paused until the user explicitly authorizes further inspections.
- Production changes and live payment tests require separate explicit approval.

## 2. Implementation issues

### 0058-01 — Domain ownership and decision register
**Objective:** Lock ownership across Catalog, Inventory Core, Acquisition/COGS, Pricing, Orders/POS, Auction, Returns, Shipping/Pickup, and Analytics.

Acceptance:
- [ ] SKU/catalog ownership is assigned.
- [ ] Store/location scope is decided.
- [ ] Serialized versus quantity-based stock rules are documented.
- [ ] Landed-cost allocation ownership is assigned.
- [ ] Reservation owner references are defined.
- [ ] Build 001/008/017 overlaps are reconciled.
- [ ] Decisions and unresolved items are versioned.

### 0058-02 — Application and environment readiness
**Objective:** Establish a safe non-production implementation baseline.

Acceptance:
- [ ] Repository branch and working tree are reviewed.
- [ ] Existing application routes, data access patterns, and package scripts are documented.
- [ ] Development and production environments are clearly separated.
- [ ] Secret handling and environment-variable conventions are documented.
- [ ] Non-production Supabase target is confirmed.
- [ ] Backup and recovery expectations are recorded.
- [ ] Build 004 server-side session and actor-resolution status is verified when inspection is authorized.

### 0058-03 — Database preflight and migration approval
**Objective:** Validate actual database state before executable migrations.

**Blocked until the user explicitly authorizes resuming database inspections.**

Acceptance:
- [ ] Relevant schemas and migration history are inspected.
- [ ] Tables, views, sequences, functions, triggers, constraints, indexes, policies, grants, and ownership are inventoried.
- [ ] Candidate object names are reconciled against existing objects.
- [ ] Build 004 identity objects are preserved.
- [ ] RLS and least-privilege access are reviewed.
- [ ] Identifier protection and uniqueness strategy are approved.
- [ ] Migration order, preconditions, verification, and recovery are reviewed.
- [ ] Explicit approval is recorded before any migration is applied.

### 0058-04 — Inventory foundation schema
**Objective:** Implement approved SKU references, locations, serialized units, quantity lots, and protected identifiers.

Acceptance:
- [ ] SKU/catalog references follow approved ownership.
- [ ] Location model supports approved store scope.
- [ ] Serialized units and quantity lots are distinct.
- [ ] A serialized unit cannot be double-counted as quantity stock.
- [ ] Identifier normalization, uniqueness, and access restrictions are enforced.
- [ ] Foreign keys, checks, and indexes match approved design.
- [ ] RLS/grants/policies enforce server-only mutation boundaries.
- [ ] Non-production migration verification is recorded.

### 0058-05 — Movement ledger and corrections
Acceptance:
- [ ] Every stock transition creates traceable movement history.
- [ ] Ordinary application roles cannot rewrite/delete movement history.
- [ ] Corrections use compensating movements.
- [ ] Movement writes are atomic with state changes.
- [ ] Actor, reason, correlation, and idempotency references are retained safely.
- [ ] Ledger reconciliation tests pass.

### 0058-06 — Receiving and inspection
Acceptance:
- [ ] Receipt lines reconcile with received units/lots.
- [ ] Receiving is permission-gated and idempotent.
- [ ] Receipt, stock creation, movement, and outbox event are atomic.
- [ ] Inspection records include condition, test outcomes, defects, evidence references, inspector, and timestamp.
- [ ] Invalid lifecycle transitions are rejected.
- [ ] Duplicate receiving cannot duplicate stock.
- [ ] Build 017 retains return/refund decision ownership.

### 0058-07 — Holds and reservations
Acceptance:
- [ ] Hold creation/release is permission-gated and auditable.
- [ ] Reservations reference authoritative order/cart/auction ownership.
- [ ] Serialized units cannot be allocated twice.
- [ ] Quantity allocations are concurrency-safe.
- [ ] Expiry/release is server-controlled and idempotent.
- [ ] Commit validates the owning commerce transaction.
- [ ] Parallel reservation tests demonstrate no overselling.

### 0058-08 — Availability and reconciliation
Acceptance:
- [ ] Availability accounts for on-hand, reservations, holds, and lifecycle state.
- [ ] Location scope is enforced.
- [ ] Response includes freshness/as-of metadata.
- [ ] Website and POS use the same service result.
- [ ] Reconciliation detects drift among ledger, stock records, reservations, and projections.
- [ ] Discrepancies are reported, not silently overwritten.

### 0058-09 — Transfers and adjustments
Acceptance:
- [ ] Transfers validate authority over both locations.
- [ ] Source and destination movements are atomic and balanced.
- [ ] Adjustments require elevated permission, reason, and evidence.
- [ ] Corrections preserve history through compensating movements.
- [ ] Duplicate commands are idempotent.
- [ ] Transfer/adjustment tests pass.

### 0058-10 — Outbox and event consumers
Acceptance:
- [ ] Outbox event commits with its source state change.
- [ ] Event schema is versioned and allowlisted.
- [ ] Consumers tolerate at-least-once delivery and deduplicate.
- [ ] Retry/dead-letter handling is observable.
- [ ] Payloads exclude raw identifiers, secrets, payment credentials, and unnecessary personal data.
- [ ] Each downstream consumer has clear ownership.

### 0058-11 — Channel integrations
Acceptance:
- [ ] POS resolves SKU and reserves/commits through Inventory Core.
- [ ] Storefront reads authoritative availability and requests reservations.
- [ ] Auction allocation uses the same reservation/commit rules.
- [ ] Shipping/pickup records authorized handoff transitions.
- [ ] Build 017 return disposition calls the approved inventory command.
- [ ] Analytics consumes approved events/read models and cannot mutate stock.
- [ ] No consumer writes directly to inventory tables.

### 0058-12 — Security, privacy, and operations
Acceptance:
- [ ] Anonymous and unauthorized access tests pass.
- [ ] Forged actor, role, cost, price, location, and availability claims are rejected or ignored.
- [ ] Location authorization is tested.
- [ ] Protected identifiers are redacted from logs/events/analytics.
- [ ] Audit history is reviewable.
- [ ] Backup/restore and recovery are demonstrated.
- [ ] Monitoring covers failed writes, reservation conflicts, outbox backlog, and reconciliation drift.
- [ ] No unresolved critical/high security or data-integrity findings remain.

### 0058-13 — Pilot and production release gate
Acceptance:
- [ ] Critical unit, integration, security, concurrency, idempotency, event, failure, and reconciliation tests pass.
- [ ] Non-production pilot workflows are accepted.
- [ ] Staff permissions and exception procedures are documented.
- [ ] Deployment and recovery plans are approved.
- [ ] Pull-request review is complete.
- [ ] Explicit production authorization is recorded.
- [ ] Post-release monitoring and reconciliation owners are assigned.

## 3. Dependency order

```text
0058-01 Domain decisions
  -> 0058-02 Environment readiness
  -> 0058-03 Database preflight and approval [paused]
  -> 0058-04 Foundation schema
  -> 0058-05 Movement ledger
  -> 0058-06 Receiving and inspection
  -> 0058-07 Holds and reservations
  -> 0058-08 Availability and reconciliation
  -> 0058-09 Transfers and adjustments
  -> 0058-10 Outbox and consumers
  -> 0058-11 Channel integrations
  -> 0058-12 Security and operations
  -> 0058-13 Pilot and release gate
```

Event-consumer work may proceed alongside later workflows after the outbox foundation is stable, but no consumer may become a second inventory authority.

## 4. Pull request checklist

- [ ] Correct feature branch; no unapproved production change.
- [ ] Build 004 identity and permission ownership preserved.
- [ ] Cross-build domain boundaries preserved.
- [ ] Server-side input validation, actor resolution, permissions, and location scope implemented.
- [ ] Mutations are transactional, concurrency-safe, and idempotent.
- [ ] Movement history remains auditable.
- [ ] Sensitive values are excluded from logs, events, and broad responses.
- [ ] Migrations are additive and verified in non-production.
- [ ] Automated tests and evidence are attached.
- [ ] Monitoring and recovery implications are documented.

## 5. Status vocabulary

Use: **Proposed**, **Ready**, **In progress**, **Blocked**, **In review**, **Verified**, or **Deferred**. A commit or design document alone does not make a feature Verified.

## 6. Current status

This document is a planning backlog only. It does not create GitHub Issues, code, migrations, database objects, automated tests, or deployments. Further database inspections remain paused. Production remains untouched.
