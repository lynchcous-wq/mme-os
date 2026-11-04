# Build 005.30 — Inventory Enterprise API, Integration Gateway, and Developer Documentation

**Status:** API and integration architecture design only  
**Branch:** implementation/build-005-inventory-core  
**Scope:** Defines the service boundary and integration standards for MME Inventory Core. This document is a contract-design artifact, not an implemented API. No endpoints, credentials, webhooks, queues, database objects, code, tests, or deployments were created.

## 1. Purpose

Provide one secure, versioned, auditable interface through which the MME website, POS, auction engine, returns, warehouse/mobile tools, analytics, and approved external systems request inventory information or operations.

Inventory Core remains authoritative for inventory facts and stock-changing decisions.

## 2. Integration principles

- Server-side authorization is mandatory for every protected operation.
- Clients never supply trusted actor identity, role, cost, margin, or final availability.
- Read operations and commands have distinct contracts.
- Commands are idempotent and concurrency-safe.
- Events are durable, versioned, and replay-safe.
- Sensitive identifiers and restricted financial data are minimized.
- Every contract has an owner, schema version, error model, and deprecation policy.
- No external integration receives broader access than its business purpose requires.

## 3. Service ownership and consumers

Inventory Core owns:
- SKU and physical-unit references;
- serialized and quantity-controlled inventory;
- locations and custody;
- receipts, inspections, and inventory movements;
- holds and reservations;
- availability decisions;
- inventory reconciliation references.

Consumers and boundaries:
- **Build 001 Website:** catalog-linked availability and reservation requests.
- **Build 002 Orders/POS:** order allocation, commitment, release, and sale references.
- **Build 005.17 Warehouse/Transfers:** location and custody commands.
- **Build 005.18 Scanning:** scan resolution and label references.
- **Build 005.19 Counts:** count sessions, variance review, and approved adjustments.
- **Build 005.20 Procurement:** purchase and receipt handoff.
- **Build 005.22 Auctions:** listing holds and release/settlement handoffs.
- **Build 005.23 Returns/Repair:** returned-unit intake, disposition, and parts movements.
- **Build 026 Analytics:** restricted read models and metrics.
- **Approved external channels:** narrowly scoped availability or fulfillment integrations.

No consumer may directly mutate inventory tables or bypass Inventory Core command validation.

## 4. API surface categories

Proposed API groups (illustrative resource names, not deployed routes):

### Catalog and identity references
- resolve SKU and product reference;
- resolve barcode or approved identifier;
- retrieve unit/lot summary;
- retrieve permitted location reference.

### Inventory reads
- get availability by SKU, condition, channel, fulfillment method, and location;
- retrieve unit/lot status;
- retrieve location stock summary;
- retrieve movement history within authorized scope.

### Receiving and inspection
- open or reference receipt;
- record accepted receipt lines;
- submit inspection results;
- route discrepancies for review.

### Inventory operations
- put away;
- transfer dispatch and receipt;
- place/release hold;
- create/expire/release reservation;
- commit inventory against an authorized order;
- submit count results;
- submit approved adjustment;
- record disposition.

### Integration operations
- inspect event delivery status;
- request authorized replay;
- reconcile a source reference;
- retrieve integration health within permission scope.

Each command must define required fields, validation, permissions, idempotency, concurrency behavior, side effects, and audit evidence.

## 5. Command envelope

A proposed command envelope contains:
- command ID;
- schema/API version;
- command type;
- correlation ID;
- idempotency key;
- authenticated service/user context resolved server-side;
- requested location scope;
- entity references;
- command payload;
- client timestamp for diagnostic purposes only.

The server must assign authoritative actor identity, receipt time, authorization result, and committed outcome. Client timestamps or metadata cannot override server facts.

## 6. Response envelope

A successful response should include:
- operation result;
- authoritative entity references;
- resulting state/version;
- server timestamp;
- correlation ID;
- replay/idempotency indicator where applicable;
- next permitted workflow reference, if any.

A response must not imply a payment, shipment, receipt, or sale completed unless the owning authority confirms that state.

## 7. Idempotency and concurrency

- Require idempotency keys for all non-repeatable commands.
- Scope keys to authenticated actor/service and operation.
- Store request fingerprint and final result for safe retries.
- Reject reuse of a key with a different payload.
- Use optimistic version checks or atomic constraints for conflicting updates.
- Enforce one active allocation per serialized unit.
- Prevent quantity reservations beyond eligible stock.
- Define safe conflict responses and retry guidance.
- Never automatically retry a non-idempotent external side effect without a durable deduplication strategy.

## 8. Event gateway and delivery

Proposed event envelope:
- event ID;
- event type and schema version;
- aggregate/entity reference;
- source service;
- occurred-at and recorded-at timestamps;
- correlation and causation IDs;
- payload with minimized data;
- integrity/deduplication metadata.

Delivery architecture should support:
- transactional outbox;
- authenticated consumers;
- inbox deduplication;
- bounded retry with backoff;
- dead-letter queue and operator review;
- replay with original event identity;
- schema compatibility checks;
- delivery monitoring and reconciliation.

Events communicate confirmed state changes. They are not commands and must not be treated as proof that a downstream action completed.

## 9. Authentication and authorization

- Authenticate human users through the approved Build 004 identity/session path.
- Authenticate service-to-service callers using managed credentials and rotation.
- Resolve permissions and location scope server-side.
- Enforce least privilege by consumer, command, resource, and location.
- Separate read access from mutation privileges.
- Restrict cost, margin, supplier, customer, and serial/IMEI fields.
- Validate webhook signatures, timestamps, and replay windows.
- Rate-limit public and partner endpoints.
- Never embed service-role keys, database credentials, or privileged secrets in browser/mobile clients.

Build 004 application-side session and actor enforcement is not yet verified; production integration remains gated on that validation.

## 10. Validation and error model

Use stable machine-readable error categories:
- authentication required;
- permission denied;
- resource not found or not visible;
- invalid state transition;
- validation failure;
- duplicate/idempotency conflict;
- concurrency conflict;
- insufficient eligible availability;
- stale version;
- dependency unavailable;
- rate limited;
- internal failure.

Errors should include a safe message, stable code, correlation ID, and retryability guidance. Do not reveal whether restricted records exist or expose internal stack traces, secrets, or identifiers.

## 11. Versioning and compatibility

- Version public contracts explicitly.
- Prefer additive optional fields where compatible.
- Do not silently change field meaning, enum semantics, or state transitions.
- Publish schema examples and migration notes.
- Maintain consumer compatibility windows.
- Deprecate with notice and measurable usage evidence.
- Validate event consumers against supported schema versions.
- Keep contract versions separate from internal implementation versions.

## 12. Observability and operations

Monitor:
- request volume, latency, and error rate;
- authorization denials;
- idempotency conflicts;
- reservation/commit conflicts;
- event lag, retry, and dead-letter counts;
- stale channel projections;
- reconciliation backlog;
- consumer health and schema failures.

Logs must use correlation IDs and avoid full serial/IMEI, payment credentials, customer secrets, and unnecessary personal data. Define alert ownership, severity, runbooks, and incident escalation before launch.

## 13. Developer documentation and contract testing

Required documentation:
- service ownership and architecture diagram;
- API and event catalog;
- schemas and sample requests/responses;
- authentication and permission model;
- idempotency and concurrency guidance;
- state-transition diagrams;
- error-code reference;
- local/non-production setup instructions;
- synthetic test fixtures;
- consumer onboarding and deprecation policy;
- operational runbooks and incident contacts.

Contract tests should validate schemas, authorization boundaries, idempotency, concurrency, event deduplication, replay, and backward compatibility. Tests must use synthetic data and non-production credentials.

## 14. Acceptance criteria

- [ ] Inventory Core is the only authority for stock-changing commands.
- [ ] Each consumer has documented scope and least-privilege access.
- [ ] Every command defines validation, permissions, idempotency, and concurrency.
- [ ] Client-supplied actor/role/cost/availability claims are not trusted.
- [ ] Responses report only confirmed authoritative outcomes.
- [ ] Events are durable, versioned, deduplicated, and replay-safe.
- [ ] Error responses are stable and do not leak restricted data.
- [ ] API and event versioning policies are documented.
- [ ] Observability includes event lag and reconciliation health.
- [ ] Contract tests cover security, retries, concurrency, and compatibility.
- [ ] Secrets remain outside source control and client applications.
- [ ] Production access is gated on verified Build 004 session and authorization enforcement.

## 15. Completion boundary and next gate

This is a design specification only. No API endpoint, gateway, event broker, webhook, service credential, or external connection was created. No code, database changes, tests, or deployments were performed.

Database preflight remains paused at the user's request. Production remains untouched.

**Next gate:** Approve API consumers, command scope, authentication method, event delivery platform, versioning policy, service objectives, and developer onboarding requirements before implementation.
