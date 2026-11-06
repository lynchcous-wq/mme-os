# Build 010.66 — Enterprise Customer Relationship Management

## Implemented
- Customer profiles with unique customer number, optional linked auth user, contact channels, marketing consent timestamp and customer status.
- Case-insensitive unique email and phone lookup index.
- Sales lead pipeline with status, priority, assigned representative and estimated value.
- Interaction timeline for calls, email, SMS, meetings, notes, web chat and store visits.
- Auditable interaction RPC.
- Assigned follow-up task register with due dates.
- Customer support ticket and message registers, including internal-note marker.
- Authenticated staff API, CRM dashboard, RLS, service-role-only table access and acceptance tests.

## Production blockers
- Customer profile creation is not yet linked to canonical MME identity/person records; duplicate matching, merge review, account recovery and customer/employee dual-role protections remain.
- CRM GET currently loads all staff-visible rows (capped at 500) and role check is broad. Implement server-side per-store/team/record scope, pagination, field masking and audit for every read/write before production.
- Assigned representative/employee IDs are accepted from request; verify against employee directory, active employment, role and store scope.
- Lead status and ticket updates are direct service-role table updates; add transactional state-transition RPCs, assignment authorization and audit trail.
- Marketing consent currently records a timestamp but not consent source, policy version, channel-specific opt-in, withdrawal, suppression list or proof. SMS/email must honor TCPA/CAN-SPAM and applicable privacy requirements.
- Interaction recording_reference is a metadata field only. No telephony integration, caller ID, recording capture, retention controls or notice/consent checks are present.
- Customer purchases, POS transactions, subscriptions, rewards, warranties, returns/refunds and financing are not integrated.
- Customer self-service portal, verified identity matching, email/SMS dispatch, call center routing, SLA escalation and omnichannel provider webhooks are not implemented.
- Ticket internal-note access is not separately restricted in the API. Add customer-visible vs staff-only authorization and prevent accidental disclosure.
- Customer deletion/export/retention workflows, PII encryption strategy, audit immutability and incident response review remain.
- Implement idempotency, rate limits, CSRF/origin strategy, pagination, concurrency tests and row-level scope policies.

## Validation
Run `npm run test:build010:crm`, identity, POS, support and security suites, `npm run lint`, and `npm run build`. Tests not executed, migration not applied, not merged or production deployed.
