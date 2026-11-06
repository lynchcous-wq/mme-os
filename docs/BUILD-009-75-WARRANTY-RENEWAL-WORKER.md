# Build 009.75 — Warranty Renewal Automation Worker

## Delivered
Adds a durable renewal worker queue, scan-run audit records, a 30/60/90-day scan RPC, bounded batch claiming with SKIP LOCKED, lease tokens, lease expiry recovery, completion and retry/dead-letter RPCs.

## Scan eligibility
The scan only considers lifecycle records whose status is active and whose coverage end is populated and falls inside the relevant lead window. It only considers active campaigns with approval actor and timestamp and whose effective dates include the scan time. Opportunities are unique per lifecycle and horizon; deterministic idempotency keys prevent duplicate work. Repeated scans are safe.

## Worker safety
Claim batches are limited to 100 and leases are bounded. Completion/failure must present the current lease token. Expired leases can be reclaimed. Failures use bounded retry delays and attempts; exhausted jobs become dead-letter items for operator review.

## Guardrails
The worker queues review work only. It does not generate prices, auto-approve offers, send messages, bypass marketing consent or charge customers. Offer preparation requires an approved pricing snapshot and separate offer approval in a later integration. Notification delivery remains owned by the consent-aware communications worker.

## Operations
A scheduler or protected service-role process must invoke the scan RPC, then claim jobs and dispatch each job type. Add operational alerting for failed runs, queue age, retry volume and dead-letter growth. Do not expose worker RPCs to browser roles.

## Validation
Run npm run lint and npm run test:build009:warranty-renewal-worker. PostgreSQL integration tests must cover exact horizon boundaries, campaign approval/effective dates, cancelled/expired lifecycle exclusion, concurrent scans, concurrent claimers, stale lease rejection, retry caps and dead-letter transitions.

## Rollout boundary
Database worker primitives and contract tests only. No scheduler, running worker process, customer notification, approved offer generation, payment provider call, production migration replay or deployment is claimed.
