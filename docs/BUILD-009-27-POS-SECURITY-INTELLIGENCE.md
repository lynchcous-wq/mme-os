# Build 009.27 — POS Hardware & Infrastructure Security Intelligence Center

Status: implementation committed to a review branch; migration replay, integration tests, security-provider validation and device-adapter testing pending.

## Reused foundation
- Build 009.20 authenticated hardware command dispatch.
- Build 009.21 device acknowledgments and uncertain-outcome reconciliation.
- Build 009.22 hardware/network health and predictive diagnostics.
- Build 009.23 hardware fleet identity and location-scoped administration.
- Build 009.24 signed firmware/configuration rollout controls and staged deployment.
- Build 009.25 network zones, secure communications observations and certificate lifecycle.
- Build 009.26 disaster incidents, recovery execution approvals and continuity evidence.

## Implemented database foundation
- `mme_pos_security_rules`: versioned detection rules; activation requires an approver.
- `mme_pos_security_events`: normalized security events with event key, source, location, device, timestamps and digest.
- `mme_pos_security_alerts`: explainable alerts, severity, optional risk score, rule version and occurrence count.
- `mme_pos_security_risk_scores`: subject-level score, factors, scoring version and assessment expiry.
- `mme_pos_security_incidents`: investigation/containment/remediation lifecycle.
- `mme_pos_security_incident_alerts`: many-to-many alert/incident links.
- `mme_pos_security_evidence`: evidence references, SHA-256 digest, sensitivity, retention and custody history.
- `mme_pos_security_actions`: controlled response requests and approval state.
- `mme_pos_security_investigations`: assigned investigator, scope, findings and conclusion.
- `mme_pos_security_audit_events`: immutable-style operational audit history (database owner/service role remains privileged).

## Detection coverage
Rules and trusted adapters may report:
- Unknown or unregistered POS devices and suspicious enrollment changes.
- Hardware tampering indicators and unexpected device state changes.
- Unexpected network peers, unencrypted sessions, certificate expiry/revocation and segmentation violations.
- Firmware/configuration drift and unsupported version observations.
- Payment terminal security posture and processor connectivity anomalies.
- Unusual administrative access, privilege changes and data export/access events.

Each event records its source, observed time, location, event type and correlation reference. Duplicate event keys are idempotent. Alert explanations must identify the rule/version, relevant event(s), evidence and contributing factors. Risk scores are advisory and versioned; no score alone proves compromise or misconduct.

## Investigation workflow
1. Trusted collectors submit normalized security observations through the service-only ingestion function.
2. A detection worker evaluates approved, enabled rules and creates explainable alerts. This migration stores the rules and alert records; it does not include a production detection scheduler or ML model.
3. An authorized security analyst triages the alert and may create/link an incident.
4. An investigator is assigned a documented scope. Evidence is referenced from approved encrypted storage, with digest, collection time and custody events.
5. The team determines whether the event is confirmed, unsubstantiated, false positive, inconclusive or a policy gap.
6. Remediation and verification are recorded before incident closure.

## Controlled response
- A containment request must identify an incident, target, action and reason.
- Actions start as pending approval and require an independent authorized approver; the requester cannot approve their own action.
- Only supported actions may be dispatched by a separately trusted adapter after approval.
- Supported action categories include requesting device isolation, disabling a device credential, certificate revocation, blocking a peer, suspending enrollment, preserving logs and notifying IT/payment provider.
- The schema does not isolate devices, revoke live credentials, change network ACLs or stop payment processing. The adapter must validate target identity, location, authorization, reversibility and result before reporting execution.
- Emergency containment must follow a separately approved MME incident-response runbook and be fully audited.

## Privacy and employee safeguards
- Do not place passwords, private keys, tokens, PAN, CVV/CVC, PIN, magnetic-stripe data or unnecessary personal data in event details or evidence metadata.
- Store raw logs, screenshots and other sensitive evidence only in approved encrypted evidence storage; the database stores references and digests.
- Restrict access by location, role, case assignment and evidence sensitivity.
- Security telemetry is not a disciplinary finding. Employee-related allegations must be independently reviewed through the authorized HR process; a risk score or alert is not proof of wrongdoing.
- Apply approved retention, legal hold and deletion policies to evidence and audit records.

## Dashboard specification (not live)
- CEO: enterprise-level security posture, critical incidents, store exposure and trend summaries; restricted raw evidence access.
- CIO / IT Security: fleet posture, network/certificate/firmware alerts, rule health and response queue.
- Loss Prevention Manager: assigned incidents, evidence collection, investigation status and resolution outcomes.
- IT Manager / Technician: device-specific diagnostics and assigned remediation tasks only.
- Store Manager: limited local operational alerts and instructions; no access to restricted evidence or enterprise investigations.

## Security model
- All new tables enable RLS; direct public/anonymous/authenticated access is revoked and service role is granted.
- RPC functions are service-role only and reuse Build 009.25's hardware permission authorization gate for active employment, frozen access and location scoping.
- Rules cannot be enabled until approved. Event ingestion is idempotent and rejects future timestamps beyond tolerance.
- Action requests and approvals are separately authorized and audited.
- A production deployment must verify existing helper function signatures, permission grants and role-to-permission mappings. Do not assume a named permission is granted merely because the RPC references it.

## Validation required
Run:
- `npm run test:build009:security-intelligence`
- `npm run test:build009:disaster-recovery`
- `npm run test:build009:network-security`
- `npm run test:build009:firmware-orchestration`
- `npm run test:build009:hardware-fleet-administration`
- `npm run test:build009:hardware-health-intelligence`
- `npm run test:build009:hardware-ack-reconciliation`
- `npm run lint`
- Full ordered Supabase migration replay and PostgreSQL integration tests in an isolated environment.

Integration tests must cover duplicate event ingestion, event-key collision across stores, disabled/unapproved rule rejection, alert explainability/version capture, cross-location access denial, self-approval, evidence custody, service-role boundaries, event retention and audit completeness. Device containment adapters require hardware-in-the-loop tests before enablement.

## Not claimed complete
No migration has been applied to production Supabase. No SIEM, EDR, endpoint agent, network sensor, certificate authority, payment processor, camera/security system or physical device has been connected. No automated detection model, monitoring schedule or live containment operation has been deployed. Dashboards and scores are not live.
