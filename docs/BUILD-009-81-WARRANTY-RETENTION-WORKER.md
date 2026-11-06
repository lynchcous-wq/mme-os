# Build 009.81 — Warranty Retention Automation Worker

## Delivered
- Bounded retention-due scan RPC.
- Legal-hold and approved-exception exclusion at enqueue time.
- Idempotent deletion job generation.
- Independent approval; requester cannot approve their own job.
- Approval-time revalidation of holds, exceptions and retention eligibility.
- Concurrent worker claim using SKIP LOCKED and bounded lease duration.
- Lease-token and expiry validation on completion.
- Final hold and exception recheck before completion.
- Verified-absence state and append-only audit event.
- Service-role-only worker RPC execution.

## Worker protocol
1. A trusted scheduler invokes the bounded enqueue RPC.
2. An authorized privacy/compliance approver independently approves an eligible job.
3. A worker claims an approved job and receives a lease token.
4. The worker resolves the exact private object from the evidence record, deletes it through a private storage adapter, then independently verifies absence.
5. The worker submits the job ID, lease token and storage deletion reference to the confirmation RPC.

The database RPCs provide orchestration only. They are not a scheduler or storage deletion implementation. A successful delete response alone is not proof of absence. Production approval APIs must derive staff identity and role from authenticated sessions, not client-supplied IDs.

## Validation
Run npm run lint and npm run test:build009:warranty-retention-worker. Integration tests must cover due-date boundaries, hold/exception races, duplicate enqueue, self-approval, concurrent claims, lease expiry, storage failures and absence verification.

## Rollout boundary
Database RPC foundation and contract tests only. No scheduler, staff approval UI/API, storage deletion adapter, automatic retries, alerts, production migration replay or deployment is claimed.
