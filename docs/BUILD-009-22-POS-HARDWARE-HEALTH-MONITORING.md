# Build 009.22 — POS Hardware Health Monitoring & Predictive Diagnostics

Status: implementation committed to a review branch; migration replay, CI and physical-device validation pending.

## Reused dependencies
- Build 009.15 device registry, event history and IT incident workflow.
- Build 009.16 secure pairing and heartbeat supervision.
- Build 009.20 safe command dispatch and uncertain drawer quarantine.
- Build 009.21 durable provider acknowledgment ledger and reconciliation.

## Implemented schema
- `mme_pos_device_telemetry`: bounded, idempotent, timestamped numeric telemetry.
- `mme_pos_device_health_scores`: deterministic score, band, scoring version and evidence factors.
- `mme_pos_device_health_alerts`: deduplicated health alerts.
- `mme_pos_device_diagnostics`: typed diagnostic outcomes, including not-supported and unknown.
- `mme_pos_device_maintenance_tasks`: technician work queue linked to alerts.
- `mme_pos_device_baselines`: device-type and metric-specific threshold configuration with explicit higher-is-worse/lower-is-worse direction.

## Health scoring
Scores are deterministic and explainable, based on current device registry state, heartbeat age, active IT incidents, and optional recent telemetry. Bands:
- 95–100 excellent
- 85–94 healthy
- 70–84 attention
- 50–69 degraded
- 0–49 critical
- unknown where the device has not completed pairing

Missing telemetry contributes no penalty and is recorded as unavailable evidence; it is never fabricated or silently treated as a failure. The score is an operational signal, not an AI diagnosis or an employee performance assessment.

Threshold direction is explicit: latency, packet loss, error rate and temperature generally use higher-is-worse; battery and paper remaining generally use lower-is-worse. Baselines must be configured and validated for the exact model and units before enabling. No assumed vendor-specific temperature, battery, printer-paper or payment-terminal metric is treated as available.

## Automation
- Bounded service-role telemetry ingestion (maximum 12 metrics per event, approved metric keys/ranges and 24-hour event window).
- Deterministic health calculation and bounded sweep (1–1,000 devices).
- Deduplicated alerts for attention/degraded/critical/offline/heartbeat-stale states.
- Maintenance task created from a new alert; repair/replacement requires technician verification.
- Diagnostic result vocabulary includes pass, warning, fail, not_supported and unknown.
- Existing Build 009.16 heartbeat sweep continues to mark stale devices offline and open IT incidents.

## Security
- RLS enabled on all new tables; direct public, anonymous and authenticated table access revoked.
- All new RPCs are service-role only.
- Telemetry accepts only bounded numeric operational metrics, not free-form device logs or payment credentials.
- Do not ingest PAN, CVV, PIN, authentication secrets or raw provider credentials.
- Alert and score explanations use operational evidence only. No automated HR/disciplinary action is initiated.

## Validation required
Run:
- `npm run test:build009:hardware-health-intelligence`
- `npm run test:build009:hardware-supervision`
- `npm run test:build009:hardware-ack-reconciliation`
- `npm run lint`
- Full ordered migration replay and PostgreSQL integration tests in an isolated Supabase environment.

Test offline and stale heartbeat scoring, no-telemetry unknown handling, duplicate telemetry, invalid metrics, both threshold directions, alert/task deduplication, retired-device exclusion, service-role access, and bounded sweep behavior. Verify actual telemetry availability and units with each device vendor before enabling production baselines.

## Not claimed complete
No migration has been applied to the connected Supabase project, no cron/scheduler has been configured, no dashboard is represented as live, and no physical device or vendor telemetry stream has been certified.
