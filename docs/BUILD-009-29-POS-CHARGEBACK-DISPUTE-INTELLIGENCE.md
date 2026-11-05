# Build 009.29 — POS Chargeback & Payment Dispute Intelligence Engine

Status: implementation committed to a review branch; migration replay, provider webhook verification, deadline rules, evidence connector validation and processor submission integration pending.

## Reused foundation
- Build 009.20–009.26: POS hardware dispatch, state reconciliation, device health, fleet management, secure communications and business continuity.
- Build 009.27: security events, evidence custody, investigations and shared authorization gate.
- Build 009.28: fraud/anomaly event and case foundation.
- Payments Center and transaction journal: authoritative payment state, processor references and reconciliation.
- Customer Portal/order fulfillment and Build 017 return/inspection records: transaction, delivery, pickup, serial/IMEI and return evidence.

## Implemented database foundation
- `mme_pos_payment_disputes`: provider dispute identity, amount, status, store, linked transaction and response deadline.
- `mme_pos_dispute_events`: idempotent provider webhook/event inbox using provider + event reference.
- `mme_pos_dispute_evidence`: evidence source references, digest, sensitivity and verification state.
- `mme_pos_dispute_packets`: versioned evidence manifests, validation results, digest and independent approval.
- `mme_pos_dispute_actions`: idempotent, audited action requests and provider action reference.
- `mme_pos_dispute_audit_events`: actor, action, reason and dispute/store references.

## Dispute lifecycle
1. Trusted provider connector receives a signed webhook or polls a provider API. It must verify provider signature, timestamp, endpoint secret, replay protection and event identity before passing the normalized envelope to the database.
2. The webhook inbox records the provider event idempotently. Duplicate events do not create duplicate dispute work.
3. A reconciliation worker maps the provider dispute to the original processor payment, MME POS transaction, customer/order, store and any linked fraud/return records.
4. The dispute is assigned to an authorized owner. The response deadline is normalized to UTC while preserving the provider's original deadline/time-zone context in connector metadata.
5. Evidence is gathered from approved source systems. Every item has a source reference, collection time, integrity digest where available, sensitivity and reviewer status.
6. A packet generator creates a versioned manifest and runs completeness, consistency, deadline and redaction checks.
7. A reviewer validates the evidence. A different authorized approver must approve the final packet.
8. Only a separate trusted processor adapter may submit an approved packet. The provider's submission response/reference is reconciled and recorded.
9. The dispute remains open until an authoritative provider outcome is received. Win/loss, withdrawn, expired and unresolved outcomes are recorded distinctly.

## Evidence categories
- Original receipt and POS transaction summary.
- Processor authorization, capture, refund and reversal references.
- Customer communication and order/checkout terms acceptance where available.
- Shipping carrier delivery confirmation or signed delivery proof.
- Local pickup verification, where applicable and lawfully collected.
- Serial/IMEI association and inventory movement record, masked in case displays.
- Build 017 return condition, inspection, defect and warranty records.
- Published refund/return policy version effective at the time of purchase.
- Device/register audit events and other approved supporting records.

Do not manufacture evidence or backdate records. Missing evidence must be shown as missing; it must not be inferred from an unrelated record. Camera footage is included only through an approved, access-controlled evidence reference and lawful retention process.

## Deadline and escalation intelligence
- Store provider deadline and internal target deadline separately.
- Calculate remaining time from authoritative provider timestamps, not local browser time.
- Alert at configurable intervals, for example 7 days, 72 hours, 24 hours and 4 hours before deadline; exact schedules must follow each provider's actual rules and must be configurable.
- Escalate unassigned disputes, missing evidence, packet validation failures, approval delays and connector outages.
- Do not mark a dispute submitted until the provider confirms acceptance and returns a submission reference.
- If a provider deadline is missing or ambiguous, flag for immediate human verification rather than inventing one.

## Security and financial integrity
- Shared authorization gate includes dispute-specific view, manage, evidence, approve and submit permissions while preserving active identity, active employment, CEO freeze, permission expiry and store scope.
- RLS enabled; direct public/anonymous/authenticated table access revoked; trusted service role performs connector and worker operations.
- Provider webhook signatures must be validated by the connector before database ingestion. The SQL event inbox stores a digest and event identity; it does not verify provider signatures itself.
- Never store PAN, full card numbers, CVV/CVC, PIN, track data or authentication secrets. Processor tokens/references only.
- Evidence artifacts remain in approved encrypted storage; database records store references and digests.
- Packet generation and approval are separate. The packet creator cannot approve their own packet.
- Submission requires an independent approval and a trusted provider adapter. Idempotency keys prevent duplicate submission attempts.
- Dispute outcomes and recovered amounts must reconcile to authoritative processor and finance records; do not recognize provisional or disputed funds as recovered.

## Dashboard specification (not live)
- CEO: enterprise dispute exposure, deadlines at risk, confirmed wins/losses, recovery and store trends; restricted raw evidence access.
- Finance: disputed amounts, settlement status, processor references, recovered/lost amounts and reconciliation queue.
- Loss Prevention: assigned fraud-related disputes, evidence status and investigation linkage.
- Customer Service: approved customer communications and status; no unrestricted sensitive evidence.
- CIO / IT: webhook/API health, event backlog, provider sync failures, deadline calculation health and submission adapter status.
- Store Manager: limited local dispute tasks and requests for evidence.

## Validation required
Run:
- `npm run test:build009:disputes`
- `npm run test:build009:fraud-intelligence`
- `npm run test:build009:security-intelligence`
- All preceding Build 009 hardware, payment, transaction and continuity suites.
- `npm run lint`
- Full ordered Supabase migration replay and PostgreSQL integration tests.

Integration tests must cover duplicate and replayed webhooks, provider event identity collisions, forged/invalid signatures rejected by connector, deadline timezone/DST boundaries, stale provider updates, missing transaction mapping, cross-store access denial, evidence digest mismatch, missing evidence, redaction failure, self-approval, duplicate submission idempotency, provider timeout/uncertain submission reconciliation, deadline escalation, provider outcome reconciliation and audit completeness.

## Not claimed complete
No live Stripe or Verifone webhook/API integration has been connected. No processor dispute was retrieved, submitted or won. No automated deadline worker, evidence packet storage connector, provider submission adapter, live dashboard or notification channel has been deployed. No migration has been applied to production Supabase.
