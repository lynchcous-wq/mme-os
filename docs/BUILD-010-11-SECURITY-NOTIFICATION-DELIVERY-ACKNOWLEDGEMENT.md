# Build 010.11 — Security Notification Delivery & Acknowledgement

## Delivered
- Notification recipient/channel preference records.
- Delivery attempt ledger and provider receipt fields.
- Notification acknowledgement event ledger.
- Idempotency-key uniqueness support.
- Bounded concurrent-safe due-notification claim RPC.
- Retry scheduling fields and capped attempt counter.
- Authenticated notification API.
- Role/recipient-checked acknowledgement.
- Adapter-secret-protected delivery receipt endpoint.
- Notification command center, contract tests and CI.

## Dashboard
`/warranty/security-intelligence/notifications`

## Provider integration boundary
No external email, SMS, push or pager provider is connected in this change. A provider adapter must claim queued notifications, honor channel preferences, verify recipient contact details, deliver, and submit authenticated delivery receipts using `MME_NOTIFICATION_ADAPTER_SECRET`. Configure that secret only in server-side deployment secrets.

## Important limitations
- The due queue API claims notifications but does not dispatch them to an external provider.
- Delivery receipt endpoint is an integration boundary, not proof a provider exists or is configured.
- Retry timestamps and attempt limits are stored, but no scheduler/retry worker is provisioned here.
- The current status model maps accepted/delivered receipts to sent; consumers must inspect the attempt ledger for actual delivered status.
- Acknowledgement deadlines are schema-ready but not populated by this migration's existing notification creation workflow, and no missed-ack escalation worker is included.
- Preference API accepts a user ID from the caller; production must enforce self-service or admin-scoped authorization and validate recipients against the employee directory.
- No email/SMS/push provider credentials, contact data, test execution, CI run or production deployment is claimed.

## Validation
Run `npm run lint` and `npm run test:build010:security-notification-delivery-acknowledgement`. Test adapter authentication, duplicate receipts, retry scheduling, role/user acknowledgement, preference authorization, and provider webhook replay.
