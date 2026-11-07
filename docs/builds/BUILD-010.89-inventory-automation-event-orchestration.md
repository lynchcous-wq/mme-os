# Build 010.89 — Inventory Automation Rules Engine, Event Processing & Workflow Orchestration

**Status:** Additive implementation contract committed on an isolated feature branch. No live event bus, automation rules runtime, scheduled worker, workflow engine, migration, or production deployment is claimed.

## 1. Audit findings and constraints

Repository searches on the Build 010.88 line did not locate verified inventory automation rules, event-processing workers, or workflow orchestration runtime components. Build 008 defines stable event IDs, minimal payloads, idempotent API/webhook behavior, Build 006 task/notification integration, and explicit human approval boundaries, but states that the inventory architecture is a specification rather than proof of runtime implementation. Builds 010.79, 010.86, and 010.87 define reconciliation retries, scheduled forecast refresh, aging scans, alerts, tasks, escalation, and safe retries as contracts only.

Do not invent event tables, queue providers, workflow libraries, cron configuration, RPCs, canonical status values, or service credentials. Inspect the current application architecture, deployment platform, Supabase schema/RLS, existing background jobs, provider webhooks, Build 006 task/notification service, audit service, and actual production configuration before implementation. Select one durable event/queue authority and document ownership. Do not create a competing queue or duplicate task system.

## 2. Objective

Provide a governed automation control plane that:
- Accepts verified domain events from canonical MME OS services.
- Validates, versions, deduplicates, persists, routes, and processes events durably.
- Evaluates approved rules against explicit event and source-state conditions.
- Starts authorized workflows and assigns tasks to the owning service.
- Retries transient failures safely and quarantines poison/permanent failures.
- Exposes operational status, traceability, pause/kill switches, and audit evidence.
- Preserves human approval for inventory, price, procurement, customer, payment, and accounting actions.

Automation is orchestration, not a new source of truth for products, inventory, orders, prices, payments, suppliers, employees, or accounting.

## 3. Event envelope contract

Every event must carry a validated, versioned envelope with:
- Stable event ID and event type.
- Schema version and producer/service identity.
- Aggregate type and stable aggregate reference.
- Event occurrence time and ingestion time.
- Correlation ID and causation/parent event reference.
- Idempotency/deduplication identity.
- Legal-entity and location scope where applicable.
- Minimal, non-sensitive payload.
- Trace context and producer contract version.

Requirements:
- Validate schema and producer authorization before acceptance.
- Reject unknown or incompatible schema versions safely.
- Treat payload as untrusted input; never execute embedded instructions or arbitrary code.
- Do not include passwords, tokens, payment credentials, unnecessary customer PII, or raw serial/IMEI in general event payloads.
- Keep restricted data in its authoritative service and pass a protected reference where needed.
- Preserve immutable event identity and delivery history.
- Record payload hash/version for conflict detection without logging sensitive payload contents.

Candidate event families (only enable after producer contracts are verified):
- Catalog/product published or changed.
- Inventory movement posted or rejected.
- Reservation created, committed, released, or expired.
- Sale/fulfillment milestone confirmed by its authoritative owner.
- Receiving accepted or inspection exception raised.
- Transfer dispatched, received, or discrepancy recorded.
- Cycle count completed, variance approved, or compensating adjustment posted.
- Return inspected and disposition approved.
- Cost/valuation/COGS posting succeeded or failed.
- Approved price version changed.
- Forecast/replenishment recommendation created or approved.
- Lifecycle aging threshold crossed or disposition case updated.
- Website availability sync succeeded or failed.
- Reconciliation run completed or exception detected.

An event name alone is not proof that a business action is authorized or complete. Consumers must verify the canonical source state and required approval.

## 4. Rule engine contract

A rule is a versioned, reviewed configuration containing:
- Stable rule ID, name, owner, purpose, and version.
- Enabled/disabled state and environment.
- Allowed producer/event types and schema versions.
- Explicit conditions, filters, thresholds, and scope.
- Permitted action type and target service.
- Required source-state verification.
- Approval policy and authorized approver roles.
- Deduplication key and rate/quiet-period policy.
- Retry and timeout policy.
- Effective dates, expiry, and change history.
- Test fixtures, expected outcomes, and rollout status.

Rules must be declarative and allowlisted. Do not evaluate arbitrary JavaScript, SQL, shell commands, templates with code execution, or user-supplied executable expressions. Validate rule configuration at save and activation time.

Rule lifecycle: draft → reviewed → approved → staged → active → paused/disabled → retired. Rule edits create new immutable versions. Activation requires an authorized reviewer distinct from the author for high-impact rules.

## 5. Workflow orchestration

A workflow instance records its definition/version, triggering event, correlation, current step, source references, state, owner, timestamps, retry count, approvals, and audit trail.

Required behavior:
- Explicit state transitions with preconditions.
- Durable checkpoints and recovery after worker restart.
- Timeouts, deadlines, escalation, and cancellation semantics.
- Compensation/saga steps only through canonical service APIs.
- Human task creation for decisions that require judgment or authority.
- Idempotent resume/replay and duplicate-trigger handling.
- Version-safe handling of workflows already in progress when a definition changes.
- No hidden side effects during retries.

A workflow may request an action from an owning service; it must not write directly to another domain's tables or bypass its authorization and approval checks.

## 6. Processing, delivery and failure semantics

- Persist or durably enqueue accepted events before acknowledging successful acceptance.
- Use at-least-once delivery with idempotent consumers unless an inspected provider guarantees a stronger documented contract.
- Acknowledge only after durable completion or durable transfer to a retry/dead-letter state.
- Use bounded exponential backoff with jitter for transient network, rate-limit, and provider failures.
- Honor provider retry-after signals and documented rate limits.
- Do not retry permanent validation, authorization, policy, or approval failures indefinitely.
- Preserve original event ID and idempotency identity across every retry.
- Detect same-ID/different-payload conflicts and quarantine them.
- Support delayed, replayed, duplicated, and out-of-order events.
- Enforce concurrency controls by aggregate/location where order matters.
- Prevent one poison event from blocking unrelated aggregates.
- Provide controlled replay with source-state revalidation and an audit reason.
- Dead-letter inspection and replay require scoped permissions and recorded operator identity.
- A notification failure must not erase or cancel the underlying business event or task.

## 7. Approved automation catalog

Initial rule candidates, subject to verified producer and consumer APIs:

| Trigger | Permitted automation | Prohibited automatic action |
|---|---|---|
| Low stock / projected stockout | Notify buyer; create recommendation task | Issue PO or commit funds |
| Reservation nearing expiry | Notify owner; request canonical expiry/revalidation | Release a paid/committed order |
| Receiving inspection failure | Create quarantine/inspection task | Release or restock unit |
| Transfer discrepancy | Open case and notify both locations | Change source/destination balance |
| Count variance | Route evidence for independent review | Post adjustment without approval |
| Inventory posting failure | Retry canonical posting idempotently; open exception | Create a second stock movement |
| Aging threshold crossed | Create review/markdown recommendation | Change selling price |
| Return inspection completed | Route approved disposition request | Automatically restock or write off |
| Cost/COGS mismatch | Notify finance; create reconciliation case | Change cost, GL, or invoice state |
| Website stock sync failure | Retry sync; mark feed stale and alert | Invent available quantity |
| Forecast refresh failed | Retry and show stale forecast state | Create purchase order |
| Dashboard source stale | Notify service owner; mark data stale | Replace missing values with zero |

High-impact actions such as stock movement, adjustment, transfer approval, price change, purchase commitment, refund, write-off, disposal, cost adjustment, and accounting posting remain in their owning workflows with required approval.

## 8. Human approval and safety controls

- Every action maps to an explicit permission and authoritative service endpoint.
- Recheck user/service identity, scope, current source state, and approval at execution time.
- Bind approval to exact payload, quantity, item/location, price/cost version, and proposal version.
- Any material change invalidates prior approval and requires resubmission.
- Enforce separation of duties for configured high-risk actions.
- Provide global automation pause, per-rule pause, per-producer circuit breaker, and per-consumer pause.
- Kill switch stops new side effects while preserving durable events and current workflow state.
- Resume requires health checks, backlog review, and authorized action.
- Dry-run mode records proposed matches/actions without executing side effects.
- Canary activation and staged rollout are required for new rules.
- Rules cannot expand their own permissions or approve their own actions.

## 9. Observability and operations console

Expose a role-scoped control plane with:
- Event intake, accepted/rejected counts, and schema failures.
- Queue depth, oldest event age, processing latency, and throughput.
- Consumer health, retries, timeouts, and dead-letter counts.
- Workflow instances by state, age, owner, and SLA.
- Rule versions, activation history, matches, and dry-run comparisons.
- Duplicate/conflicting event detection.
- Circuit-breaker and kill-switch status.
- Source/provider health and event coverage.
- Correlation search and redacted event/workflow timeline.
- Replay and retry actions with permission, reason, and audit trail.

Do not display raw secrets, payment credentials, customer PII, or unrestricted serial/IMEI. Use bounded pagination and scoped safe references.

## 10. Security, privacy and audit

- Authenticate producer identities and authorize event types/scopes server-side.
- Use least-privilege service identities, short-lived credentials where supported, and server-only secrets.
- Enforce tenant/legal-entity/location and role scopes at every consumer and action boundary.
- Apply RLS where Supabase is the verified persistence authority.
- Validate payload size, schema, references, and rate limits.
- Protect webhook endpoints with provider signature verification, replay protection, and timestamp tolerance where applicable.
- Encrypt sensitive data in transit and at rest according to platform controls.
- Audit rule creation, review, activation, pause, edits, event replay, manual retry, approval, workflow transition, and side-effect request.
- Retain minimal data under approved retention policy; avoid copying sensitive records into queue payloads.
- Separate operational telemetry from restricted business records.

## 11. Reliability, scaling and cost

- Establish event retention, retry horizon, maximum attempts, dead-letter retention, and replay windows.
- Bound worker concurrency, per-provider throughput, queue depth, payload size, and workflow duration.
- Use backpressure and circuit breakers to protect Supabase, POS, checkout, payments, and other critical systems.
- Prevent unbounded fan-out and notification storms through deduplication, grouping, quiet periods, and escalation policies.
- Ensure scheduled tasks use stable schedule identity, timezone, missed-run policy, and run idempotency.
- Measure end-to-end event age, not only worker execution duration.
- Define recovery objectives and backlog-drain procedures before production activation.

## 12. Acceptance and regression tests

- Valid producer event is durably accepted and receives a stable identity.
- Invalid schema, unauthorized producer, wrong scope, and oversized payload are rejected.
- Duplicate delivery results in one business side effect.
- Same event ID with conflicting payload is quarantined.
- Out-of-order and late events do not corrupt canonical state.
- Transient failure retries with original idempotency identity; permanent failure stops and opens an exception.
- Worker crash/restart resumes from durable checkpoint without duplicate side effects.
- Dead-letter replay requires permission, reason, source revalidation, and audit.
- Rule version changes do not silently rewrite active workflow history.
- Dry-run has no side effects; kill switch blocks side effects and preserves events.
- Approval is invalidated when the underlying action payload changes.
- Location/legal-entity scopes and sensitive-field redaction are enforced.
- Notification failure does not cancel a business task or event.
- Queue load/backpressure protects POS, checkout, payment, warehouse, and inventory write paths.
- Regression tests preserve customer sign-in, employee sign-in, product catalog, POS, warehouse, receiving, transfers, reservations, counts, returns, valuation/COGS, forecasting, lifecycle, and reporting behavior.

## 13. Runtime implementation gates

Do not mark Build 010.89 implemented or live until:
1. Existing app, provider, database, job, webhook, notification, task, and audit architecture is inspected in the target environment.
2. The authoritative event transport/persistence and workflow execution model are selected and documented.
3. Producer and consumer contracts, schema versions, source ownership, and event retention are approved.
4. Rule catalog, approval matrix, allowed actions, kill switches, and separation-of-duties policy are approved.
5. Durable event intake, rule evaluation, worker processing, retry/dead-letter, workflow persistence, and operations UI are implemented additively.
6. Every side effect is routed through canonical authenticated APIs and tested for idempotency.
7. Security, RLS, privacy, observability, load, failure recovery, and replay tests pass.
8. Staging proves no unauthorized inventory, pricing, procurement, payment, return, or accounting mutation.
9. Regression tests preserve customer/employee sign-in, product viewing, POS and preceding inventory workflows.
10. Operations, finance, security, and executive owners approve rollout; deployment and post-deploy evidence record exact commit, environment, queue health, and measured event latency.

**Release note:** This contract is not a live queue, event bus, worker, rules engine, scheduler, workflow service, inventory mutation, migration, or deployment approval. No runtime automation capability is claimed by this document.
