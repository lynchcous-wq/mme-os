# Build 009.83 — Warranty Compliance Command Dashboard

## Delivered
- Read-only KPI projection for retained, overdue, deletion approval backlog, failed deletion, legal holds, active exceptions, high-risk alerts and notification backlog.
- Retention calendar with 7-day, 30-day and overdue windows, policy lineage and hold/exception indicators.
- Deletion approval queue with queued, blocked, approved and failed states.
- Open/acknowledged alert feed.
- Assignment/severity department summary.
- Five security-invoker views; browser roles denied and service_role granted read access.

## Dashboard contract
The dashboard is an executive and compliance read model, not a customer evidence viewer. Do not render file objects, object keys, IMEIs, serial numbers, customer contact data or raw evidence payloads. Role authorization and row scoping must be enforced by the authenticated server/API layer before exposing any view. Department summary currently groups by assignee UUID bucket, not an authoritative HR department; a future identity/HR join is required before calling it department performance. KPI counts are live database aggregates, not forecasts.

## Rollout boundary
SQL read models only. No frontend cockpit, authenticated API routes, chart components, export service, scheduled refresh, role-mapping integration, production migration replay or deployment is claimed.

## Validation
Run npm run lint and npm run test:build009:warranty-compliance-dashboard. Database integration tests must validate security-invoker behavior, role isolation, counts against seeded records, timezone boundaries and no cross-customer evidence disclosure.
