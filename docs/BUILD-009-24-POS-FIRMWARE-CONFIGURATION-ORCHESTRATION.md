# Build 009.24 — POS Hardware Firmware & Configuration Update Orchestration

Status: implementation committed to a review branch; migration replay, automated execution and vendor/hardware validation pending.

## Reused foundation
- Build 009.15 hardware registry and IT incident workflow.
- Build 009.16 trusted pairing and device heartbeat supervision.
- Build 009.20 command dispatch and uncertain-outcome safety.
- Build 009.21 acknowledgment and state reconciliation.
- Build 009.22 telemetry and device health diagnostics.
- Build 009.23 device fleet, assignment, configuration proposals and two-person administration approvals.

## Implemented schema
- `mme_pos_firmware_packages`: manufacturer/model/device compatibility, target version, artifact object key, SHA-256 digest, signature metadata, publisher, release notes and vendor-supported rollback metadata.
- `mme_pos_configuration_templates`: versioned configuration templates with canonical digest and approval state.
- `mme_pos_deployment_campaigns`: firmware/configuration rollout campaign, stage, failure threshold and lifecycle.
- `mme_pos_deployment_targets`: per-device target state, current/target version, preflight evidence and execution outcome.
- `mme_pos_deployment_events`: append-oriented campaign and target event history.
- `mme_pos_deployment_approvals`: expiring two-person approval.
- `mme_pos_deployment_recovery`: separately approved recovery requests.

## Workflow
1. Firmware artifacts are held in controlled object storage. This migration stores metadata and object keys, not firmware bytes.
2. An external trusted verification process must validate publisher signature, package digest, provenance and vendor compatibility before setting a package to verified. The database metadata flag is not itself cryptographic signature verification.
3. Configuration templates are versioned, digest-bound and approved separately.
4. A campaign selects 1–500 registered devices. The database verifies the full target set exists, each device is online/non-retired, compatibility and location permissions pass.
5. A different authorized person approves the campaign. Approval expires after 24 hours.
6. Before dispatch, a trusted adapter records fresh idle-state and compatibility checks (within two minutes). The dispatch authorization function rejects stale preflight evidence, unapproved campaigns or revoked packages/templates.
7. The external dispatcher executes only through the approved Build 009.20 adapter and records Build 009.21 acknowledgments. This migration does not itself send commands or install firmware.
8. Failure-rate evaluation pauses the campaign and blocks pending targets when the configured threshold is exceeded. Failed and uncertain outcomes count toward the threshold.
9. Recovery is a separate request and two-person approval. Vendor rollback requires explicit verified vendor support; reinstall requires a verified previous package. No universal rollback capability is assumed.

## Rollout stages
Supported campaign labels are lab, canary, pilot, regional and enterprise. The execution worker must enforce stage promotion gates and verify successful completion at each stage before moving to the next. The database campaign stage field is not, by itself, proof that a stage passed.

## Security and operational safeguards
- New tables use RLS and direct public/anonymous/authenticated table access is revoked.
- Privileged functions are service-role-only and call existing location-scoped hardware permission checks.
- Requester cannot approve own campaign or recovery.
- Exact device set, hardware compatibility, active device status, package verification and recent preflight are required.
- No firmware or configuration update may run during an active transaction. The trusted adapter must independently verify idle state immediately before dispatch.
- A timeout/uncertain device result is not retried blindly. Reconcile device state through Build 009.21 first.
- Payment terminals must never be updated while a payment is pending or unresolved.
- Failed update, health degradation or loss of connectivity pauses the rollout and opens the existing IT incident path.
- No raw payment PAN, CVV, PIN, credentials or firmware binaries are stored in the campaign database.

## Validation required
Run:
- `npm run test:build009:firmware-orchestration`
- `npm run test:build009:hardware-fleet-administration`
- `npm run test:build009:hardware-health-intelligence`
- `npm run test:build009:hardware-ack-reconciliation`
- `npm run lint`
- Full ordered Supabase migration replay and PostgreSQL integration tests in an isolated environment.

Integration tests must cover package digest/signature verification gates, compatibility mismatch, missing/duplicate device IDs, inactive devices, expired/self-approval, cross-location permission, stale preflight, pending transaction block, campaign pause on failure, uncertain outcome reconciliation and recovery approval.

## Not claimed complete
No migration is applied to the connected Supabase project. No firmware artifact is uploaded or cryptographically verified by this code alone. No physical device update, vendor API integration, staged worker, scheduler, rollback or production deployment is active. A real vendor adapter and hardware test bench are required before enabling rollout.
