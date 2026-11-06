# Build 010.07 — Security Provider Failover & Circuit Breakers

## Delivered
- Persistent circuit state for seven source systems.
- Closed, open, half-open and manual-open states.
- Default three-failure threshold and 60-second open interval.
- Database admission and outcome-recording RPCs.
- Primary and secondary provider URL routing in the source adapter gateway.
- Five-second provider request timeout.
- Failover event history.
- CEO/CIO/IT-admin circuit inspection and manual override API.
- Provider failover dashboard.
- Contract tests, CI and documentation.

## Configuration
For each source, configure `MME_PROVIDER_PRIMARY_POS` and `MME_PROVIDER_SECONDARY_POS` (replace POS with INVENTORY, WARRANTY, CRM, EVIDENCE, PAYMENTS or RETURNS). The primary URL may fall back to `MME_INTERNAL_APP_URL`. Provider endpoints must accept the same central signed-ingestion contract and preserve event ID idempotency.

## Routing
The adapter requests circuit admission before routing. A closed circuit tries primary then secondary after a failed primary attempt. An open circuit routes to secondary. After the open interval, one half-open primary probe is admitted. A successful response closes the circuit. All attempts retain the original event ID.

## Manual controls
GET `/api/warranty/security-intelligence/provider-failover` and POST with `source`, `action` (open/close) and a reason. Requires CEO, CIO or IT administrator app-metadata role.

## Limitations and safety gates
- The secondary provider must be an independently deployed compatible endpoint. Merely pointing primary and secondary at the same deployment is not genuine redundancy.
- Database RPC admission serializes half-open probes. Validate service-role execution and transaction behavior in staging.
- Circuit state updates are separate from the provider HTTP request; transient database failure can leave state stale. Monitor RPC failures.
- Manual close transitions to half-open, not directly closed.
- No provider health synthetic probes, latency-based scoring, weighted routing or multi-region quorum.
- HTTP non-success responses are treated as provider failures; refine retryability by status code before production.
- Event ID idempotency must be enforced by every secondary target to prevent duplicates after ambiguous network timeouts.
- No deployment, live failover, production verification or automated tests are claimed.

## Validation
Run `npm run lint` and `npm run test:build010:security-provider-failover-circuit-breakers`. Stage primary timeout, HTTP 5xx, secondary success, all-provider failure, half-open probe concurrency, manual override authorization and duplicate delivery.
