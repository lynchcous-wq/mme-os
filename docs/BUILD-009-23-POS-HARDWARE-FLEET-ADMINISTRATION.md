# Build 009.23 — POS Hardware Fleet Management & Remote Device Administration

Status: implementation committed to a review branch; database replay, CI and operational validation pending.

## Reused foundation
- Build 009.15 hardware registry and IT incident workflow.
- Build 009.16 secure pairing, provider metadata and heartbeat supervision.
- Build 009.20 safe hardware command delivery and uncertain-outcome handling.
- Build 009.21 acknowledgment ledger and state reconciliation.
- Build 009.22 telemetry, health scoring, diagnostics and maintenance tasks.

## Implemented schema
- Extended `mme_pos_register_devices` with manufacturer, model, serial, firmware/adapter version, warranty, installation, retirement and bounded notes.
- `mme_pos_device_assignments`: assignment history, with only one active assignment per device.
- `mme_pos_device_lifecycle_events`: actor, transition, reason and approval history.
- `mme_pos_device_configuration_versions`: bounded versioned JSON configuration and digest, with separate draft/approval/application states.
- `mme_pos_device_admin_approvals`: expiring approval requests for sensitive actions.
- `mme_pos_device_admin_actions`: operational audit record for administration activity.

## Workflows
1. Register and pair a device through the existing trusted provider pairing flow.
2. Record inventory metadata and serial identity; serial uniqueness is enforced where a serial is supplied.
3. Assign/reassign devices to a location and register. Reassignment closes the previous assignment record and opens a new one.
4. Sensitive lifecycle operations require a separate approver; the requester cannot approve their own request.
5. Approval is bound to the exact operation and, for reassignment, the approved destination location and register. Expired or mismatched approvals are rejected.
6. Configuration changes are versioned and proposed for approval. Approval returns `approved_pending_deployment`; it does not itself dispatch or apply configuration to a physical device.
7. Diagnostics continue through the Build 009.22 supported diagnostic record path. Arbitrary remote shell, unsupported firmware flashing, and unreviewed commands are not introduced.

## Lifecycle
Supported device states remain aligned with the existing registry: pending, online, offline, maintenance and retired. State changes are reasoned, permission-checked and recorded. Retired hardware cannot be reassigned. Reactivation returns through a pending enrollment path.

## Authorization and security
- Reuses active identity, active employment and CEO employee-access-freeze checks.
- Adds explicit permission keys for administration, assignment, configuration, approval and retirement.
- Location scope is checked for both source and destination when reassigning.
- Sensitive actions require distinct requester and approver identities.
- Approval requests expire; operation payload must match the approved action.
- RLS enabled and direct public/anonymous/authenticated table access revoked on new tables. New RPCs are service-role only.
- Provider credentials remain external secret references; no raw credentials, payment PAN, CVV or PIN are stored.
- Configuration approval is not hardware execution. Build 009.24 remains responsible for controlled firmware/configuration rollout.

## Validation required
Run:
- `npm run test:build009:hardware-fleet-administration`
- `npm run test:build009:hardware-health-intelligence`
- `npm run test:build009:hardware-ack-reconciliation`
- `npm run lint`
- Full ordered migration replay and PostgreSQL integration tests in an isolated Supabase environment.

Test duplicate serials, simultaneous assignments, cross-location permission denial, missing/expired/self-approval, mismatched reassignment payload, lifecycle/action mismatch, retired-device restrictions, configuration approval without dispatch, and RLS/service-role boundaries.

## Not claimed complete
No migration has been applied to the connected Supabase project. No real-time dashboard, remote command console, physical device changes, configuration deployment, firmware update, or production activation is claimed.
