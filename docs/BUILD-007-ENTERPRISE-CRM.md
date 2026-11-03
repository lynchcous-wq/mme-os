# Build 007 — Enterprise CRM & Customer Relationship Intelligence Engine
## GitHub Platform Edition

**Company:** Much More Electronics  
**Platform:** GitHub for source control, automation and deployment governance; MME OS backend for CRM operations and authoritative business records  
**Build number:** 007  
**Status:** Specification for implementation approval; not implemented  
**Authority:** CEO, exercised through approved governance, access controls and audit  
**Dependencies:** Builds 001–006  
**Repository:** `lynchcous-wq/mme-os`

## 1. Purpose and architecture boundary

Build 007 defines a centralized CRM for customer relationships from inquiry through purchase, service, subscriptions and retention. It connects customer accounts, sales representatives, inquiries, calls, leads, opportunities, quotations, financing status, transactions, follow-ups, service, promotions and retention intelligence.

The CRM runs inside MME OS using frontend interfaces, authenticated backend services, customer/CRM data stores, versioned APIs, approved communication/telephony integrations, the Build 006 workflow engine, and centralized audit. MME OS is authoritative for its CRM/customer relationship records. Connected modules expose controlled APIs/events; the CRM does not silently overwrite customer account, order, pricing, payment, HR, subscription, or return system-of-record data.

GitHub manages source code, reviewed configuration, integration docs, tests, Issues/Projects for engineering work, and approved CI/CD. GitHub is not the production customer database. Customer records, call details, payment information, credentials, confidential commercial data, or sensitive identifiers must not be stored in ordinary GitHub Issues, commits, Actions logs or artifacts.

This specification does not claim that a CRM, database, identity provider, telephony provider, email/SMS service, website integration, or source-module API exists. Verify actual Replit/runtime and GitHub configuration before implementation. The current repository is a storefront shell with placeholder routes and documentation; preserve it and implement additively.

## 2. CRM module boundaries and source-of-truth rules

| Data/domain | Authoritative owner | CRM behavior |
|---|---|---|
| Login identity and authentication | IAM/approved identity provider | Link using stable opaque identity IDs; do not make email the permanent key |
| Customer account and customer relationship | Customer Account System | CRM reads authorized identity/contact/status fields and routes changes to owner |
| Employee relationship/status and employment records | HR; access grants owned by Identity Matrix | Separate employee and customer relationships; CRM does not infer employee permission from profile data |
| Leads, opportunities, customer interactions and CRM cases | CRM | CRM is authoritative for its own records, assignment, stage, notes and interaction references |
| Products/specifications/media | Product Catalog | CRM reads published product version; no unapproved product edits |
| Approved selling prices/promotions | CEO-authorized Pricing/Marketing systems | CRM quotes only approved active values; discount exceptions route to Deal Desk/approval |
| Orders, sales and transaction status | POS/Order Management | CRM displays authorized references and status projections; it does not mark sales complete |
| Payment/refund state | Payments Center/provider and Returns service | CRM shows permitted processor references/statuses, never raw card data/CVV |
| Financing application status | Approved financing provider/Financing Center | Minimize CRM data; display only necessary authorized status and follow-up reference |
| Subscription/rewards status | Subscription/Rewards systems | CRM consumes entitlements/status; MME Rewards card remains distinct from in-house financing |
| Tasks/notifications/approvals | Build 006 Task/Notification/Approval services and source modules | CRM emits authorized workflow commands/events; Build 006 owns task/approval lifecycle |
| Calls/recordings/delivery status | Approved telephony/communications provider, with MME OS event log | Retain minimal references and outcomes; provider remains source for provider-side call state/media |
| Analytics | Governed BI projections | CRM reports are derived, permission-filtered and traceable, not an alternate write source |

## 3. Customer identity and account model

### 3.1 Customer identity requirements

Support one customer account per verified email address under the approved identity policy, a unique opaque customer ID, contact details, account creation time, customer-relationship status, purchase/subscription history references, rewards reference, communication preferences/consent, assigned representative, and customer service history.

Email is a verified contact/lookup attribute, not a durable primary key. Use stable IDs and provider subject mapping. Define email changes, account recovery, duplicate resolution, merge/unmerge authorization, and identity-proofing procedures before production. Do not automatically merge records based only on matching name, phone, postal address, caller ID, device, or unverified email. Potential duplicates enter a restricted review workflow with provenance and audit; preserve source links and history if approved merge occurs.

### 3.2 Customer and employee relationship separation

A person may have one login identity/email linked to both a customer relationship and employee relationship. Those relationships and their statuses are independent. Employee termination removes/reviews employee grants and sessions according to Build 004; it must not automatically deactivate the customer account. Customer restrictions do not terminate employment. An account freeze must state which relationship or login/session is affected, reason, authority, scope, duration/review date, and restore path.

### 3.3 Customer profile sections

- **Identity:** customer ID, display name, verified contact references, preferred/allowed communication methods, account status.
- **Customer activity:** first/last interaction, purchase count/value and transaction value only where source definitions are approved, last purchase, assigned representative, open opportunities.
- **Commerce:** online/in-store order references, returns/refunds, quotations, financing status, subscriptions and rewards references.
- **Communication:** authorized call/email/text records, inquiries, follow-up tasks and consent/preference history.
- **Service:** open/closed case references, complaints, warranty inquiries, resolution status and feedback where permitted.

Apply field-level permission and data minimization. Customer-facing and employee-facing views differ by access. Payment credential data remains with approved providers; CRM may display safe transaction ID/reference, amount/currency where permitted, and provider status, never raw card number, CVV, authentication secret, or full bank credential.

## 4. CRM data model and history

Proposed entities (implementation schema and retention remain ADR decisions):

| Entity | Core fields / responsibility |
|---|---|
| CustomerProfile | Opaque customer ID, identity link, relationship state, created/updated version and owner |
| ContactPoint | Type, normalized value/reference, verified state/time/source, preference/consent reference and lifecycle |
| Lead | Lead ID, source, customer/person reference if known, interest, estimated value/status, owner, timestamps, follow-up |
| Opportunity | Stage, value/currency estimate, product interest, attribution, expected close, owner and history |
| Assignment | Lead/customer/opportunity, assigned user/team, assigner, effective date, reason, history |
| Interaction | Channel, direction, time, actor, purpose, outcome, safe summary, consent/basis, provider reference and correlation ID |
| CallRecord | Provider call ID, inbound/outbound, authorized agent, routing, timestamps, result, masked caller reference, recording status/reference if permitted |
| QuoteReference | Deal Desk quote ID/version, item/price references, expiry and delivery/acceptance status |
| ServiceCase | Case ID/category, severity, status, assigned queue/user, related references, resolution and history |
| FollowUp | Reminder/task reference, channel, due time, owner and outcome; task lifecycle owned by Build 006 |
| CommunicationTemplate | Version, category, approved text/assets, variables, owner, approval and lifecycle status |
| ConsentRecord | Purpose/channel, status, source, scope, timestamp, policy version, withdrawal and evidence reference |
| FinancingReference | Provider and application reference, minimum status, timestamp; restricted sensitive content excluded |
| SubscriptionReference | Subscription system ID, type/status/renewal/benefit references as authorized |
| AuditEvent | Actor, action, target, time, outcome, reason/approval reference, correlation and version history |

Keep append-only/versioned history for material changes, assignments, stages, consent and outcomes. Corrections use attributable updates or compensating events, not silent deletion. Use stable identifiers, UTC timestamps, explicit currency, schema versions and source provenance. Define retention/deletion/legal hold and customer access/correction workflows according to reviewed legal requirements.

## 5. Telephone system and MME Super-Number

The “Super-Number” is an intended centralized company telephone identity implemented through an approved telephony provider; the provider and capabilities are not selected or verified by this document.

### 5.1 Required capabilities

Subject to provider support and configuration: main company number, inbound routing, outbound caller ID, department/representative queues, authorized customer lookup, missed-call tracking, voicemail, call history, call outcome and follow-up generation. Display caller-associated CRM data only after authenticated employee authorization and reliable match confidence; caller ID can be spoofed or shared and is not proof of identity.

### 5.2 Incoming calls

1. Provider sends a signed/authenticated event with provider call reference and minimized caller metadata.
2. Integration validates signature, timestamp/replay, provider/account identity and payload.
3. CRM performs a restricted candidate lookup; ambiguous/no match must not expose a customer profile.
4. Authorized agent may see a minimum necessary profile/call context and follow an identity verification procedure before discussing protected account details.
5. Agent may create a lead or customer record after appropriate validation; duplicate prevention and review apply.
6. Call event, agent, routing, result and follow-up reference are recorded with audit/correlation; customer data is not copied into provider logs unnecessarily.

### 5.3 Outgoing calls

Authenticated staff initiate calls using a provider integration scoped to their permissions. Company number caller ID is used only where supported/authorized. Enforce approved caller ID and destination policies, prevent one employee impersonating another, record the actual authenticated initiator, and audit call initiation/outcome. Provider call failure is distinct from CRM follow-up completion.

### 5.4 Recording and voicemail

Recording is disabled unless an approved provider, policy, lawful basis/consent/disclosure workflow, jurisdiction review, retention, access controls and deletion/legal-hold process have been approved. Recording legality varies by jurisdiction and situation; do not assume every call may be recorded. If recording is enabled, capture required notice/consent evidence, status, provider reference and access history; restrict playback/download to a narrowly authorized role and purpose. Secure media storage, encryption, retention limits, access logging, and deletion controls are required. Voicemail follows equivalent privacy, access and retention controls.

## 6. Lead and opportunity management

### 6.1 Sources and stages

Lead sources may include website inquiries, in-store visits, incoming/outgoing calls, social media, advertising, referrals, financing inquiries and subscription inquiries. Record source attribution/provenance and consent/basis where relevant. Anonymous visitor activity must remain aggregate/pseudonymous unless the person identifies themselves through an approved interaction; never represent anonymous events as a known customer.

Lead fields: lead ID, known customer/person reference if verified, source, product interest, estimated purchase value/currency, assigned representative/team, created/last-contact/next-follow-up timestamps, status, consent state and history.

Stages: New → Contact Attempted → Contacted → Qualified → Product Recommended → Quotation Sent → Financing Discussion → Negotiation → Sale Completed, Lost or Future Follow-Up. Define allowed transitions and required fields. “Sale Completed” is sourced from POS/Order Management, not a manual CRM assertion. Lost and future-follow-up outcomes require reason/next date where policy requires.

### 6.2 Assignment

Support authorized manual, manager, department, round-robin and workload-based assignment, plus approved reassignment. Assignment rules need an owner, eligible staff set, capacity/availability input, fairness policy, conflict/territory scope, failure fallback and audit. CEO/authorized managers retain assignment authority. Do not assign based on sensitive characteristics or use an opaque algorithm without reviewed policy. Reassignment records actor, reason, source and prior/new owner.

## 7. Sales representative workspace and follow-up

Representatives see assigned leads/customers/opportunities, authorized interaction history, follow-up deadlines, quote references, personal sales performance and authorized commission data. They may schedule calls/text follow-ups, use approved email templates, record notes, update permitted stages, request management help and ask for reassignment.

All material interactions are recorded with actor, time, channel, purpose/outcome and safe summary. Notes must be professional, relevant, minimal and subject to retention/access policy; avoid sensitive personal data not necessary for the business purpose. Build 006 owns task assignment/status/reminders/escalations; CRM stores references and business context. A missed follow-up can create a task/notification but cannot automatically trigger discipline.

## 8. Communication templates and consent

Maintain versioned, approved templates for welcome, new-customer follow-up, product recommendations, quotes, financing information, subscription/rewards announcements, order/pickup/shipping, return updates, support responses and review requests. Templates may use validated customer/product/employee/store fields, approved branding/links and safe signatures. Preview and validate variables; prevent unsafe HTML/link injection and incorrect pricing/promises. Company name, logo and store contact details come from approved brand/configuration sources.

Marketing and promotional communications must check current purpose/channel consent and applicable opt-out/suppression rules at send time. Transactional/service messages are separately classified and still require provider/legal review. Record consent source, time, policy/version, scope, withdrawal and synchronization status. Do not infer consent from a purchase, phone call, website visit, or existing customer status. Suppression takes precedence over a stale CRM preference. Protect unsubscribe and preference changes from accidental overwrite by integrations.

Email/SMS/push providers are not selected. Message previews must not expose sensitive financial, HR, case, or payment data. Delivery status is provider-reported and distinct from customer engagement or task completion.

## 9. Website and commerce integrations

Capture only approved, consent-aware events: account registration, identified inquiry, declared product interest, cart activity under approved analytics rules, completed order, subscription purchase, financing inquiry and support request.

Website-to-CRM flow: backend validates input and anti-abuse limits → identity/customer matching uses verified fields and safe duplicate handling → identified inquiry creates/updates lead under idempotency key → assigned team is notified through Build 006 → authorized event/history is available in CRM. Anonymous events remain aggregate and are never falsely represented as identified customers. Public APIs expose no unrestricted CRM collections, customer search, employee notes, internal lead scores, call details or confidential activity.

Completed orders, payment state, product/pricing, returns and subscriptions come from their source modules. CRM receives stable references and authorized status events; it does not treat an untrusted client event or browser redirect as a completed sale/payment.

## 10. Deal Desk, quotations, financing and subscriptions

### 10.1 Deal Desk and quotation

Representative creates a quote request using published product and active approved selling price → promotion/discount validation → exception request routes through Deal Desk/Build 006 approval → quote is issued only with authorized price/terms/version → delivery and customer response tracked → accepted quote becomes an opportunity/order through the owner. CRM cannot independently override CEO-authorized pricing or convert a quote to a paid sale. Expiry, revision, rescission and version history are explicit; changed pricing invalidates prior approval as defined by policy.

### 10.2 Financing

Show inquiry, approved provider reference, application status, required-document indicator, follow-up and final status only as authorized. Do not store unnecessary financial application information or provider credentials in CRM. Provider/Financing Center is authoritative for application decisions. CRM/AI may not approve financing or imply approval from a pending status.

### 10.3 Subscriptions and rewards

Display current subscription status/type, renewal date and benefits from Subscription Management with freshness and source. Keep MME Rewards Credit Card information separate from MME in-house financing and subscription membership. Do not imply credit approval or financing terms based on subscription/rewards status.

## 11. Customer service and retention

Case categories: product inquiry, shipping/pickup issue, payment question, return/refund inquiry, warranty, subscription, complaint and technical support. Case flow: receive → create ID → classify/assign → acknowledge using authorized channel → investigate → record resolution/action reference → update customer → close under authorized policy. Source systems remain authoritative for orders, payments, shipping, warranty and returns. A CRM case closure does not itself execute a refund or service action.

Retention indicators may identify repeat customers, inactive accounts, upcoming subscription renewals, unresolved issues, eligibility for approved promotions and engagement trends. Use documented, non-discriminatory criteria and authorized data. Marketing action requires current consent and active approved campaign/offer; avoid sensitive-inference targeting. AI can suggest a follow-up or summarize patterns but cannot trigger an unauthorized campaign, promise an outcome, or make consequential eligibility decisions.

## 12. AI customer relationship intelligence

Allowed, scoped assistance may summarize authorized interaction history/cases, recommend follow-up timing, identify overdue leads, suggest relevant published products, detect aggregate service patterns, draft communications and generate management summaries.

Controls:

- AI is optional assistance, not a source of truth. Label recommendations/drafts and show source/provenance, timestamp and uncertainty where relevant.
- Tool access is enforced by backend identity/policy, not prompts. AI sees only authorized minimum data and cannot elevate permissions.
- Human review and current consent/policy checks are required before outbound communication or workflow execution.
- AI must not approve financing, alter approved prices, issue refunds, change permissions, make unsupported promises, or independently make consequential customer/employee determinations.
- Do not send restricted customer, call recording, HR, payment or financial data to an external model until privacy/security/vendor/retention/residency review is approved.
- Evaluate accuracy, hallucination, bias, privacy leakage, prompt injection from customer messages/documents, logging/retention, rollback and kill switch. Preserve attribution of human edits and final actions.

## 13. CRM analytics and Build 005/006 integration

Authorized reports may include leads created/contacted/conversion, opportunities, quotes sent/accepted, completed sales and representative attribution; new/repeat customers, retention, customer value, source acquisition and case response/resolution; and calls, follow-ups, assignment, conversion, feedback and authorized commissions.

Metrics require definitions, source modules, denominator, date/timezone/currency, attribution and status policy. A lead conversion is not a sale unless the source order confirms it. Financial figures reconcile to POS/Orders/Accounting; employee comparisons are permission-limited. Visualization may include tables, bars, lines, funnels and activity trends with accessible alternatives, freshness and actual/estimate labels.

CRM events integrate with Build 006 for new/unassigned leads, overdue follow-up, expiring quotation, unanswered inquiry, financing status change, subscription renewal, escalated complaint and unresolved case. Events include stable IDs, schema version, correlation, minimal payload and idempotency. Build 006 owns task/notification/approval records and escalation lifecycle. Notification failures do not cancel CRM records or customer service obligations.

## 14. Security, privacy and data governance

- Identity Matrix role/action/record/department/location scope is enforced on backend APIs, UI data, search, exports, calls, notes, attachments, reports and administrative operations.
- Least privilege; secure authentication/session management; MFA/step-up for privileged access; scoped service identities; prompt revocation.
- Encrypt communications and sensitive persisted data; manage secrets outside source; validate inputs; rate-limit public inquiry and lookup endpoints; protect against IDOR, account enumeration, CSRF, mass assignment and injection.
- Classify customer contact details, interaction notes, call metadata, recordings, financing references, consent and complaint data. Mask/minimize fields, restrict exports and sensitive reads, and audit access according to purpose.
- Do not put customer or payment data in GitHub Issues, commits, Actions output/artifacts or source fixtures. Use synthetic data for tests and scan logs/artifacts for leakage.
- Use secure file/media storage with access checks, type/size validation, malware controls where available, retention and deletion/legal hold.
- Define privacy notice, consent, access/correction/deletion, retention, cross-border transfer, breach response and legal review before production; requirements vary by jurisdiction.
- Back up and restore test CRM data under approved RPO/RTO and retention policies. Audit administrative changes, customer merges, bulk exports, consent changes, call recording access, assignment and sensitive profile access.

## 15. GitHub development and deployment governance

Before using GitHub settings, inspect repository owner, plan/features and current configuration. Establish, where supported and approved: private source repository, protected production branch/rulesets, CODEOWNERS, required review and checks, restricted admin/Actions permissions, dependency/secret/code scanning, release versioning, development/staging/production environments, required production deployment approvals and integration documentation.

Use least-privilege GitHub Actions tokens and reviewed/pinned Actions; use OIDC and short-lived provider credentials where supported. Separate environment secrets. Never print customer/employee/payment records or API keys in workflow output. GitHub workflow approval is deployment governance, not approval of a CRM business transaction. No integration is assumed to exist merely because it appears in this specification.

## 16. Implementation phases

### Phase 1 — GitHub and project discovery

Inspect the current repository, Replit runtime/deployment, auth/data services, workflows, existing routes and tests. Verify repository settings and providers. Record current behavior, gaps, risks and preservation plan. Do not create a replacement CRM scaffold or separate repository without explicit architecture approval; the existing MME OS repository is the current project context.

### Phase 2 — CRM foundation

Select data/persistence and API architecture in ADRs; define identity link, customer profile, contact verification/consent, lead/opportunity, assignment and interaction schemas; implement migrations with rollback, audit, access controls, duplicate review and retention.

### Phase 3 — CRM interface and workflows

Add customer profiles, pipeline, rep workspace, follow-up links to Build 006, cases and controlled search. Keep existing storefront intact and expose no fake customer data.

### Phase 4 — Communications and telephony

Select and review providers, jurisdiction/consent policies, super-number setup, routing, caller ID, call events, messaging templates and recording policy. Start with recording disabled unless specifically approved and legally validated.

### Phase 5 — Business integrations

Connect website, POS/Orders, Deal Desk, Customer Portal, Financing Center, Subscription/Rewards and approved CRM communication providers through documented authenticated contracts, idempotency, monitoring and sandbox tests.

### Phase 6 — Intelligence and release

Add governed reporting and scoped AI assistance after data lineage, consent, permission filters, evaluation, human review and stop controls. Test using synthetic/staging data, security/privacy review, rollback and operational runbooks before production rollout.

## 17. Acceptance criteria and verification plan

Build 007 is ready for implementation approval when evidence demonstrates:

- [ ] CRM customer profiles, leads/opportunities, assignments, interactions, cases and histories have named owners, schemas, retention and authoritative-source boundaries.
- [ ] One verified email maps to a customer account under defined identity/recovery rules; duplicate matching does not automatically merge ambiguous people.
- [ ] Employee and customer relationships remain independent; employee termination does not automatically deactivate customer access.
- [ ] Lead stages, manual/manager/department/round-robin/workload assignment, reassignment, permissions and histories function under policy.
- [ ] Sales representative views expose only assigned/authorized customer data; manager and executive scopes are tested.
- [ ] Telephone integration validates provider events; caller ID is not treated as proof of customer identity; outgoing initiator is attributable and impersonation prevented.
- [ ] Call recording remains disabled unless provider, legal/consent, access, secure storage, retention and deletion controls are approved and verified.
- [ ] Follow-up tasks/notifications integrate with Build 006 without duplicate task creation; overdue status alone does not trigger discipline.
- [ ] Templates are versioned/approved, variables validated, and promotional sends check current consent/suppression at send time.
- [ ] Website anonymous traffic remains anonymous; identified inquiries are validated, duplicate-safe, idempotent and permission protected.
- [ ] Quotes use active approved pricing; discount exceptions require the owning approval; CRM cannot independently change price or mark a sale/payment complete.
- [ ] Financing, subscriptions and rewards display source status accurately; rewards card and in-house financing remain distinct; no raw payment credentials are stored.
- [ ] Customer service cases track lifecycle while source modules execute payments, returns, fulfillment and warranty actions.
- [ ] AI output is labeled, provenance-aware, scoped, reviewed before communication, and cannot perform prohibited actions.
- [ ] CRM metrics reconcile with source records, distinguish estimates from verified results, and apply permission-filtered drill-down/export.
- [ ] Security tests cover public API exposure, IDOR, account enumeration, data exports, consent changes, call/recording access, merge permissions, provider/webhook spoof/replay and audit.
- [ ] Sensitive customer data is absent from GitHub source, Issues, commits, Actions logs and artifacts; tests use synthetic data.
- [ ] Existing storefront functionality is preserved; implementation commit, environment, test results, reviewer and known gaps are recorded.

Minimum negative tests: unverified email account duplication; ambiguous caller match revealing a profile; employee accessing an unassigned customer; terminated employee with active CRM session; anonymous visitor falsely linked to a customer; stale opt-out allowing promotional SMS; forged/replayed telephony event; unauthorized recording playback; quote using stale/unapproved price; CRM changing payment state; financing data overcollection; unauthorized customer export; AI sending an unreviewed message; and customer record leakage in Actions logs.

## 18. Open decisions before implementation

1. CRM datastore, deployment, search/indexing, API and backup/recovery choices.
2. Identity provider, customer account ownership, verified email and account merge/recovery rules.
3. Customer ID format, duplicate detection signals, manual review owner and merge/unmerge procedure.
4. Telephony provider, number portability/ownership, routing, call event APIs, caller-ID policy, voicemail and recording decision by jurisdiction.
5. Email/SMS/push providers, consent evidence, preference precedence, message retention and opt-out synchronization.
6. CRM roles, customer record scope, sensitive-field access, manager/CEO visibility and bulk export controls.
7. Lead stages, assignment fairness/capacity policies, sales attribution and follow-up service levels.
8. Quote/discount thresholds, Deal Desk contract, expiry and approval binding.
9. Financing and subscription providers/API fields and minimum necessary CRM status.
10. Website platform and event integration selection; Wix is mentioned in planning inputs but must not be assumed without verification.
11. AI provider, allowable data, model retention/residency, evaluation, human review and opt-out/kill switch.
12. Metric definitions, attribution, consent-aware analytics, retention schedules and applicable legal jurisdictions.

## 19. Current completion boundary

This file records the Build 007 CRM architecture and acceptance specification only. No CRM data store, customer identity service, lead pipeline, call/super-number integration, recording, communication provider, website sync, Deal Desk integration, financing/subscription sync, service-case engine, AI intelligence or CRM reporting is established or verified by this document. Do not declare Build 007 implemented or complete until changes are added to the existing MME OS project, providers and settings are verified, acceptance tests pass in the actual deployment environment, and accountable business/security owners review the evidence.
