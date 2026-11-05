# Build 009.26 — POS Network Disaster Recovery & Business Continuity Engine

Status: implementation committed to a review branch; migration replay, integration tests, backup restore drills and store failover validation pending.

## Reused foundation
- Build 009.20 hardware command dispatch and retry/idempotency safeguards.
- Build 009.21 device acknowledgment and uncertain-outcome reconciliation.
- Build 009.22 hardware/network health monitoring.
- Build 009.23 fleet administration and location-scoped permissions.
- Build 009.24 staged firmware/configuration rollout safety.
- Build 009.25 network zones, secure connection observations, certificate lifecycle and incident records.

## Implemented database foundation
- `mme_pos_disaster_incidents`: store/service outage lifecycle and incident command ownership.
- `mme_pos_recovery_plans`: service recovery priorities, target RTO/RPO, approved runbook references and plan state.
- `mme_pos_recovery_executions`: recovery execution request, approval and outcome.
- `mme_pos_recovery_approvals`: expiring independent approval.
- `mme_pos_transaction_journal`: idempotent transaction continuity journal with payment, inventory and reconciliation states.
- `mme_pos_continuity_events`: offline, replay, reconciliation, duplicate and restoration event history.
- `mme_pos_backup_registry`: backup inventory, external object reference, encryption-key reference and checksum.
- `mme_pos_backup_verifications`: checksum, decryptability, restore-test, integrity and retention verification evidence.
- `mme_pos_recovery_verification`: execution-specific verification evidence required before success.

## Recovery workflow
1. A trusted monitor or authorized operations worker detects a store or service incident and records the affected location, service, severity, time and impact.
2. Operations selects an approved recovery plan matching the incident location and service. Enterprise-wide plans may have a null location.
3. A recovery request is created with a reason and a 24-hour approval window. The requester cannot approve their own recovery.
4. A separate authorized approver approves or rejects the request.
5. A trusted runbook worker starts the approved execution and records an external execution reference. This migration does not execute shell commands, restore a database, reroute traffic or switch providers.
6. The worker records the required recovery checks and evidence. Finalization is blocked unless verification records exist and all are passed.
7. After successful verification, the execution is marked succeeded and the incident moves to monitoring, not directly to closed. Operations must confirm service stability before closure.

## Transaction continuity journal
- A stable idempotency key and unique location/register/transaction tuple prevent duplicate journal inserts.
- Reusing an idempotency key for a different transaction is rejected.
- The journal records sale/refund/void/exchange/payment-adjustment type, currency, amounts, status, processor reference/token reference, minimized item summary, inventory sync and reconciliation status.
- A captured sale requires confirmed captured payment state. Pending, authorized, uncertain or reconciliation-required payment cannot be recorded as a completed captured sale.
- Offline queue entries remain pending until safely replayed and reconciled.
- Duplicate, missing, mismatched and conflicting records must enter manual reconciliation rather than being silently discarded.
- Journal payloads must not contain PAN, CVV/CVC, PIN, magnetic-stripe/track data or full card numbers. Sensitive card-field keys are rejected; processor tokens/references only.

## Backup and restoration controls
- The registry records backup object location, provider, checksum and external encryption-key reference. It does not store backup bytes or encryption keys.
- Verification types include checksum, decryptability, restore test, integrity and retention.
- A backup marked completed is not considered recoverable until a successful restore test has been recorded.
- Backup encryption, immutability, key custody, retention and point-in-time recovery must be implemented and verified in the selected storage/database providers.
- Recovery testing must use isolated environments and approved data-handling controls.

## Proposed RTO/RPO baselines
The migration seeds the following service plans as **draft targets only**. They are not approved SLAs or demonstrated recovery performance.

| Service | Target RTO | Target RPO |
|---|---:|---:|
| Payment reconciliation | 15 minutes | 0 confirmed transaction loss |
| POS transaction service | 30 minutes | 1 minute |
| Inventory | 60 minutes | 5 minutes |
| Identity | 30 minutes | 1 minute |
| Executive dashboard | 4 hours | 15 minutes |
| Marketing platform | 8 hours | 60 minutes |

Plans must be reviewed, linked to real runbooks and explicitly approved before execution. Actual RTO/RPO must be measured during drills and reported separately from targets.

## Security and payment safeguards
- New tables enable RLS; direct public/anonymous/authenticated access is revoked; service-role access is required.
- Recovery authorization reuses Build 009.25's active identity, employment, CEO freeze and location-scoped permission checks.
- Recovery approvals expire and require a different authorized person.
- No unconfirmed payment is treated as complete. Do not automatically retry an uncertain payment; reconcile with the processor first.
- Offline mode must be explicitly enabled by an authorized continuity workflow. This schema records events but does not itself enable offline tender acceptance.
- Payment terminals must use processor-approved continuity paths. Do not bypass network segmentation or security controls to restore payment connectivity.
- Recovery workers must be idempotent, auditable, bounded by approved runbooks and safe to resume after interruption.
- A restore or failover must not overwrite a newer authoritative dataset without a verified recovery-point decision and approval.

## Validation required
Run:
- `npm run test:build009:disaster-recovery`
- `npm run test:build009:network-security`
- `npm run test:build009:firmware-orchestration`
- `npm run test:build009:hardware-fleet-administration`
- `npm run test:build009:hardware-health-intelligence`
- `npm run test:build009:hardware-ack-reconciliation`
- `npm run lint`
- Full ordered Supabase migration replay and PostgreSQL integration tests in an isolated environment.

Integration tests must cover duplicate journal submissions, idempotency-key collision, card-data key rejection, unconfirmed payment completion rejection, cross-location recovery plan use, self-approval, expired approval, interrupted recovery, missing/failed restore verification, backup checksum mismatch, duplicate replay and processor reconciliation. Conduct documented store outage and restore drills before production enablement.

## Not claimed complete
No migration has been applied to production Supabase. No live backup provider, KMS, payment processor, network failover, offline POS mode, transaction replay worker, restore agent, monitoring scheduler or production runbook has been connected or executed. RTO/RPO values are draft targets, not guarantees.
