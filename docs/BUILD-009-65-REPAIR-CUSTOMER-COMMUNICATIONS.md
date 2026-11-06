# Build 009.65 — Repair Customer Communications & Appointments

## Purpose
Adds customer-facing repair timeline entries, contact preferences, appointment scheduling and a durable notification outbox on top of Build 009.64 repair cases. It does not duplicate the existing MME Communications Hub or notification delivery engine.

## Customer timeline
Only approved event codes and short, customer-safe messages may be published. Internal diagnostic findings, technician notes, provider claim details, serial/IMEI values and sensitive evidence must remain internal. Timeline events are append-only.

## Consent and delivery
Email/SMS delivery is queued only when the customer's recorded channel preference and opt-in permit it. The outbox contains template identifiers and minimal event metadata, not raw contact details. The existing communications/notification worker resolves verified destinations, templates, suppression, provider delivery and retry policy. Opt-out must suppress future sends. Provider callbacks must be signature-verified and replay-protected by the shared delivery system.

## Appointments
Repair appointments are tied to the owning customer and repair case, with location, type and time range. Conflicting active bookings are rejected. Authenticated API must additionally enforce staff location scope, customer identity, slot capacity, timezone presentation and rescheduling/cancellation policy.

## Security
RLS on all four tables; no direct browser table access. Service-role RPCs are callable only through authenticated APIs. Do not expose appointment details across customers. Use existing customer identity and communications preference verification rather than trusting caller-supplied destinations.

## Validation
Run npm run lint, npm run test:build009:repair-communications, and existing notification-delivery, communications-hub, customer-order-portal and warranty-repair suites. PostgreSQL integration tests must cover opt-out, duplicate enqueue, conflicting appointments, customer mismatch, timeline redaction, retries and provider webhook replay.

## Rollout boundary
Draft implementation only. No customer UI, SMS/email provider dispatch, calendar integration, live slot-capacity service, production migration replay or deployment is claimed.
