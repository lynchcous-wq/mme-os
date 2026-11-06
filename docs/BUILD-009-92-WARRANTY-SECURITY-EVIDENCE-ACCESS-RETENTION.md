# Build 009.92 — Warranty Security Evidence Access & Retention

## Delivered
- Server-mediated evidence download route; no public object URLs.
- Download authorization RPC requires clean scan status and checks CEO/privacy-officer roles or manager case ownership/assignment.
- Every grant/denial is recorded with actor, reason and request ID.
- Legal hold registry with one active hold per evidence item.
- CEO/privacy-officer-only legal hold placement and release API; both require reasons.
- Retention policy table with per-evidence-type day limits and enable switch.
- Retention scheduler creates due jobs from evidence collection time and configured policy.
- Atomic retention job claims skip active legal holds.
- Protected retention worker checks holds before deleting objects.
- RLS, service-role-only database functions, tests and CI.

## Download API
GET /api/warranty/security-evidence/download?evidenceId=<uuid>
Authorization: Bearer <Supabase access token>

Only clean evidence is downloadable. CEO and privacy officers can access clean evidence; managers can access clean evidence for cases they opened or lead. Legal holds preserve evidence and do not themselves prevent an otherwise authorized download.

## Legal hold API
POST /api/warranty/security-evidence/legal-hold
Actions: place {evidenceId, reason}; release {holdId, reason}. Only CEO and privacy officer app_metadata roles are accepted.

## Retention worker
POST /api/internal/warranty-security-evidence-retention
Authorization: Bearer <MME_EVIDENCE_RETENTION_WORKER_SECRET>

The scheduler/worker must be configured externally. Populate retention policies through a privileged administrative process before scheduling any deletion.

## Critical rollout boundary
No retention policies are seeded by this migration. No deletion schedule is activated. Retention deletion has a cross-system race between checking the database legal hold and deleting the object from storage; this implementation is a controlled baseline, not a legally safe immutable-retention guarantee. Before production deletion, implement a durable deletion-intent/hold-lock protocol with a second hold check and recovery reconciliation, and validate applicable legal, warranty and regulatory retention rules. Evidence metadata and audit records are retained; object deletion does not erase the evidence registry.

The download route buffers the object in memory; enforce platform request/response limits and consider streaming for larger objects. No production migration replay, storage policy verification, scheduled worker, policy configuration or deployment is claimed.

## Validation
Run npm run lint and npm run test:build009:warranty-security-evidence-access-retention. Integration tests must cover forged roles, unassigned managers, non-clean evidence, legal hold placement/release, access audit completeness, concurrent retention claims, hold/deletion race recovery, object deletion failure and retries.
