# Build 009.50 — Enterprise Customer & Employee Communications Hub

## Scope
Central campaign and announcement records, recipient eligibility, channel- and purpose-specific consent evidence, communication interaction history and campaign analytics. Delivery uses the Build 009.49 provider-neutral outbox.

## Campaign purposes
- Customer marketing.
- Transactional order/service communications.
- Employee operational announcements.
- Executive announcements.

## Consent and compliance
Marketing email/SMS/push requires affirmative, current, channel-specific marketing consent. A later opt-out supersedes earlier opt-in evidence. Unknown consent is suppressed. Unsubscribe interactions append opt-out evidence. Transactional messages are only queued from a documented business event and must not be repurposed as marketing. Before production, legal/compliance review must verify applicable federal/state requirements, sender identification, opt-out handling, quiet hours and record retention.

## Approval and access
Campaign creation, approval and dispatch are separate actions. A creator cannot approve their own campaign. Executive announcements use a separately authorized executive permission. Permission names must be provisioned through MME's permission registry before rollout; a job title is not authorization.

## Delivery
The dispatch RPC checks recipient active identity and consent before enqueueing through Build 009.49. Stable campaign/recipient idempotency prevents duplicate jobs. Actual email/SMS/push provider delivery remains in the separately deployed Build 009.49 worker.

## Interaction history
Retain sent, delivered, opened, clicked, replied, bounced, unsubscribed and failed events with channel and source references. Store provider webhook identifiers in source_reference or metadata only after PII/security review; never store raw message content or credentials in analytics.

## Analytics
Campaign-level recipient, suppression, queue, delivery and engagement metrics are exposed through `mme_communications_campaign_analytics`.

## RPCs
- `mme_communications_record_consent(...)`
- `mme_communications_create_campaign(...)`
- `mme_communications_approve_campaign(...)`
- `mme_communications_dispatch_recipient(...)`
- `mme_communications_record_interaction(...)`

## Validation
Run `npm run lint`, `npm run test:build009:communications-hub`, and `npm run test:build009:notification-delivery`. PostgreSQL integration tests must verify consent chronology, suppression, self-approval rejection, permission matrix, dispatch idempotency, identity lifecycle, webhook authenticity, unsubscribe processing and analytics accuracy.

## Rollout boundary
Implementation branch only. This migration does not send messages, connect a provider, create customer-facing UI, or claim order-system integration. Order, shipping, pickup and refund triggers must be connected to authoritative domain events before transactional campaigns can dispatch.
