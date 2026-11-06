# Build 010.31 — Notification Intelligence & Acknowledgement SLA

## Delivered
- Adds per-notification acknowledgement deadlines: critical 5 minutes, warning 15 minutes, informational 60 minutes.
- Adds acknowledgement status, timestamp, actor, note, escalation timestamp and bounded escalation level.
- Adds authenticated role-based acknowledgement RPC; CEO/CIO/IT administrators may acknowledge any routed item, while managers may acknowledge manager-routed items.
- Adds an overdue acknowledgement worker using row locks with SKIP LOCKED and escalation levels capped at five.
- Escalation writes an auditable incident response event, which flows through the existing Build 010.30 notification fan-out.
- Adds acknowledgement metrics and action to the security notification routing dashboard.
- Preserves original delivery state separately from acknowledgement state.

## Worker setup
- Set `MME_SECURITY_NOTIFICATION_ACK_WORKER_SECRET`.
- Schedule POST `/api/internal/security/notification-ack-sla` every 1–5 minutes after staging validation.
- Worker calls `mme_security_notification_escalate_unacknowledged`; service-role access only.

## Validation
- Run `npm run test:build010:notification-ack-sla`, `npm run lint`, and `npm run build`.
- Apply migration after Build 010.30 in staging and verify audience role claims, notification rows, deadlines, duplicate acknowledgement and escalation.
- Not merged, migrated, scheduled or production deployed.
