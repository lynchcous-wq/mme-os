# Build 009 — Enterprise Point of Sale (POS) & Transaction Processing Engine
## GitHub Platform Edition

**Company:** Much More Electronics  
**Development platform:** GitHub for source control, automation and deployment governance; MME OS backend for transaction workflows and authoritative records  
**Application:** MME OS  
**Build number:** 009  
**Status:** Specification for implementation review; not implemented  
**Authority:** CEO, exercised through approved business policies and audited permissions  
**Dependencies:** Builds 001–008  
**Related dependency:** Build 017 — Returns and Refunds (status and interface to be verified, not assumed)  
**Repository:** `lynchcous-wq/mme-os`

## 1. Purpose and architecture boundary

Build 009 specifies an enterprise POS for authorized retail employees to create sales, coordinate inventory reservations, process supported tenders, issue receipts, attribute sales, and synchronize approved records with accounting and commissions. It includes in-store checkout and online-order synchronization, but POS is not the authority for product catalog, inventory, customer identity, approved pricing, payment-provider status, payroll, or accounting policy.

GitHub manages source, reviewed configuration, tests, migration validation and deployment. The MME OS backend owns POS transaction workflow records and coordinates authenticated calls to the authoritative modules. Payment providers remain authoritative for processor-side authorization/capture/refund/settlement state. Never store raw card numbers, CVV, PIN, magnetic-stripe data, or sensitive authentication data in MME OS, GitHub, logs, receipts, or test fixtures. Use provider-hosted or certified payment components and token/reference-only storage.

This document is a target specification only. The repository currently contains a public storefront shell and placeholder routes; no POS, payments, tax, inventory, device, accounting, or commission integration is established or verified. Do not claim the existing Stripe account, Verifone M425 compatibility, hardware selection, or live transaction capability without independent verification.

## 2. System-of-record and module boundaries

| Domain | Authoritative owner | POS contract |
|---|---|---|
| Product details/specifications | Product Catalog | Read published product version and public/employee-authorized fields |
| Stock, reservation and movement | Build 008 Inventory | Request availability/reserve/commit/release with idempotency; never directly decrement stock |
| Customer identity/account | Build 007 Customer Account/IAM | Search only permitted fields; verify customer as required; link stable customer reference |
| Approved selling price/promotions | CEO-authorized Pricing/Marketing | Use active approved versions; discount exceptions route to approval; never silently override |
| Order/sale workflow | POS/Order Management | POS records transaction workflow; online channel order authority and conflict policy must be explicit |
| Payment status/refund/settlement | Payments Center and processor | Store provider references and verified state; reconcile asynchronously; never infer from UI response |
| Tax calculation | Approved tax provider or governed tax service | Store jurisdiction, calculation reference, rate/basis and result; do not hardcode a permanent rate |
| Return eligibility/inspection | Returns service/Build 017 if established | POS initiates/records authorized return reference; return disposition and refund are separate |
| Commission rules/calculation | Commission Management | Send attributed, eligible transaction references; POS does not calculate payroll or authorize compensation |
| Financial entries | Accounting | Submit reconciliable source transaction; Accounting owns journal policy/posting |
| Receipt logo/store standards | Central Brand/Receipt Settings | Read approved, versioned configuration; POS cannot upload/unilaterally change company policy |
| Employee authorization/audit | Identity Matrix / Central Audit Service | Enforce authenticated role, register/location and action scope server-side |

## 3. POS architecture

Logical components:

1. Employee checkout interface and authenticated register session.
2. POS transaction service and explicit transaction state machine.
3. Product/pricing lookup adapter.
4. Inventory availability/reservation adapter.
5. Customer/CRM lookup adapter.
6. Tax calculation adapter.
7. Payments Center adapter and certified terminal interface, if verified.
8. Receipt generation and print/digital delivery service.
9. Cash-drawer/register session service and device status adapter.
10. Return/refund workflow adapter.
11. Commission and Accounting event adapters.
12. Audit, reporting, reconciliation, monitoring and Build 006 notification integration.

All external/module calls are authenticated, scoped, versioned and correlated. POS uses module APIs/events, not direct cross-module database writes. The implementation topology, database, hardware provider, payment terminal SDK, tax provider, printer/drawer protocols and deployment targets remain open decisions.

## 4. Employee interface and register workflow

### Checkout layout

Use a high-speed, accessible, responsive layout with:

- Product search and barcode scanner input.
- Product categories and approved product details/images.
- Condition and availability.
- Cart lines, quantity controls, removal and cart validation.
- Customer lookup/verification and optional registration handoff.
- Separate cashier, assisting sales representative(s), supervising manager and register/store fields where applicable.
- Subtotal, approved discounts, tax, total, payment allocations, amount paid and remaining balance.
- Explicit payment state and clear error/retry states.

Suggested left/catalog, center/cart, right/customer/totals arrangement is a design option, not a requirement that compromises mobile/tablet usability. All controls must be keyboard/touch accessible, with clear focus and status announcements.

### Employee permissions

Enforce Identity Matrix permissions on product lookup, customer data, discount application, price override request, attribution, cash actions, refund/void, register close, receipt access, exports and configuration. Managers may receive scoped override/refund/review grants. CEO retains governance of critical POS permissions and company-wide policies. UI hiding is not authorization.

## 5. Product, cart and inventory flow

Product lookup may use barcode, SKU, product name, brand, model, category, or authorized serial lookup. Barcode/serial input identifies a record but never authorizes a price override, customer disclosure, inventory adjustment or transaction.

Display authorized product name, SKU, brand/model, condition, active approved price, availability, warranty and permitted specifications. Never expose IMEI/serial beyond explicitly authorized internal workflows.

### Transaction lifecycle

1. Authenticated cashier opens a register session and selects store/register.
2. POS retrieves current catalog, active price and permitted promotion versions.
3. Employee adds items and identifies customer/assisting representative when applicable.
4. POS validates quantity and requests inventory reservation using an idempotency key and expiry policy.
5. POS calculates the draft amount using approved discount and tax services; changes recalculate and preserve an audit trail where material.
6. Backend creates a payment request through Payments Center/provider; customer presents tender using approved components.
7. Payment authorization/capture status is confirmed by trusted server/provider response or verified webhook; uncertain outcomes remain pending/reconciliation-required.
8. POS finalizes a sale only under the approved order/payment policy. Inventory receives an idempotent commit/movement command tied to the authoritative transaction; uncompleted/expired orders release holds according to policy.
9. Receipt is generated from verified transaction/payment/tax data and versioned settings.
10. Commission and Accounting receive source references/events; each acknowledges or enters an exception queue.
11. POS provides an auditable completion summary and notifies the customer through an approved channel.

A declined, pending, cancelled, partial or unknown payment must not be presented as a completed fully paid sale. Inventory reservations are not sales. A client-side button, redirect, terminal UI alone, or unverified webhook cannot establish payment success. Multi-module partial completion must be visible and reconciled; do not duplicate charge or stock movement on retry.

## 6. Customer identification and sales attribution

Integrate Build 007 CRM and Build 004 identity rules. Support permitted lookup by verified email/phone/customer ID, account verification, new customer handoff, authorized purchase history, subscription/rewards status and representative assignment. Collect only data necessary for the transaction; customer remains independent from employee relationship.

Record transaction ID, cashier, assisting representative(s), supervising manager where applicable, store/register, transaction time, channel and attribution history. The employee helping the customer and the employee processing payment may differ. One or more representatives may be included only under approved attribution/commission rules. Changes require permission, reason, old/new values and audit; commission eligibility is determined by Commission Management, not POS. Do not expose other employees' restricted performance or customer history through checkout.

## 7. Tender and payment processing

### Supported tender types

Subject to provider, policy, legal and operational verification: credit/debit card, contactless, cash, approved gift card, approved financing, split tender and other explicitly authorized methods. Each method has a separate provider/settlement and reconciliation contract. Do not assume cash, gift card, financing, or offline card workflows are already supported.

### Stripe/Payments Center contract

Connect to the existing MME Stripe account only after account ownership, API credentials, terminal/product capability, environment, webhook endpoint and refund/reconciliation processes are verified. POS calls server-side Payments Center to create/confirm payment intents or supported provider operations. Use provider references and explicit state mapping for initiated, requires action, authorized, captured, failed, cancelled, refunded/partial refund, disputed and unknown/reconciliation-required states as applicable.

Requirements:

- Server-created payment requests derived from trusted cart/pricing/tax values.
- Idempotency keys bound to the transaction and operation; separate keys for authorize/capture/refund as required.
- Verify webhook signatures against raw request body; deduplicate events and validate object/account/environment before state transition.
- Treat browser/terminal client results as untrusted until server/provider confirmation.
- Handle decline, timeout, reversal, partial capture, duplicate/replayed event, delayed webhook and provider outage.
- Reconcile processor records to POS orders, tenders, refunds, settlement and Accounting; preserve exception queues and correction evidence.
- Store minimum necessary provider references/status and timestamps. Never store raw PAN, CVV, PIN, track data or sensitive authentication data.
- Keep test/live credentials separate and secret-managed. Do not expose payment secrets in browser code, source, Actions logs or artifacts.

### Split tender and balance

Represent transaction total, each tender allocation, approved financing/receivable amount, amount paid, remaining balance and tender status with currency precision. Validate sum of accepted allocations and any authorized outstanding-balance policy. Do not mark the sale fully paid when balance remains unless an approved financing/credit arrangement authorizes the transaction and its state is verified. Split tenders must be idempotent and recoverable if one tender succeeds and another fails; define void/reversal/continuation policy before production.

## 8. Verifone M425 terminal qualification

The specified Verifone M425 must be treated as an unverified target device until exact hardware, firmware, payment processor, acquiring configuration, certification, SDK/connector and deployment environment are confirmed. Do not assume Stripe Terminal supports this exact device/configuration.

Before production: confirm selected processor/acquirer and certified integration; verify device model/firmware and supported payment methods; establish secure pairing/network and device ownership; test insertion/contactless/PIN as applicable, authorization/capture, declines, reversal, refund, timeout/network loss, duplicate event and settlement reconciliation; verify terminal and POS PCI/security responsibilities with provider/acquirer guidance. If compatibility is not verified, label the integration unavailable and do not purchase/deploy on assumption.

## 9. Cash, registers, drawers and receipts

### Register/cash drawer lifecycle

A register session records cashier, register/location, opening cash and time, cash sales, cash refunds, additions/removals, authorized no-sale/manual opens, expected closing cash, actual count, variance, card/other tender summary, settlement status, close time and manager verification. Events are immutable/versioned with reason and actor. Completed close records cannot be edited without an authorized adjustment/reopen workflow and audit trail.

Drawer commands and sale/payment states are separate. On successful sale with drawer failure: preserve sale and payment status; create a hardware failure event; alert IT and store management through Build 006; assign an IT task; support only an authorized manual procedure; verify repair and document closure. Never reverse a successful payment because the drawer failed or retry a charge to operate the drawer. Cash drawer status monitoring is only claimed when supported by selected hardware/protocol.

### Receipt printer and delivery

Support selected compatible thermal printers after device testing: automatic print, authorized reprint, customer/store copy, digital receipt, printer status and failure notification. Print failure does not reverse transaction. Record print attempts/outcome and avoid duplicate receipt semantics; clearly mark reprints. Digital receipts require an approved customer channel and preference.

### Configurable receipt system

Company-managed, versioned settings may include approved MME logo; store address/phone; transaction date/time/timezone/ID; General Manager where configured; cashier and assisting representative clearly distinguished; product name/SKU/quantity/condition/unit price; discount; subtotal; tax; total; tender label and safe transaction reference; return policy; warranty details; promotion/footer content; and layout.

Receipt data comes from the finalized transaction, active approved policies and central Brand/Receipt Settings. Do not expose full payment credentials or internal IMEI/serial. CEO/company administrators govern company-wide standards; store-specific details have scoped ownership and history. Preview and validate receipt settings before activation; version configuration used on each receipt so later changes do not rewrite history.

### Review QR code

A configurable customer review QR may be enabled when an approved landing page is provided. Authorized management may update the URL through validated settings; receipt preview reflects the active version. Validate scheme/domain/redirect policy and test the rendered QR before release. Do not use an unverified or user-supplied arbitrary destination. Record settings version with the receipt. QR is not a payment or identity credential; do not encode customer/order-sensitive data.

Promotional messages about subscriptions, memberships, rewards and offers are versioned, approved and subject to applicable marketing/receipt policy. Keep MME Rewards Credit Card information separate from MME in-house financing.

## 10. Discounts, promotions and price integrity

Support fixed, percentage, category, product, subscription/membership, manager-approved and CEO-approved discounts only when configured by Pricing/Marketing policy. Each application validates eligibility, time window, code, stackability, eligible products/customer group and max threshold. Discounts do not change the authoritative base selling price.

Preserve original approved price version, discount rule/amount, approver, reason, final unit price and transaction calculation. Unauthorized discount attempts are rejected and may generate an audited alert. Manual price overrides require explicit permission and required approval, with the price service updated only through its own approval workflow.

## 11. Tax calculation

Tax is calculated for applicable jurisdictions using transaction location, product tax classification and legally relevant customer/transaction facts through an approved tax service/source. Rates and rules are not permanently hardcoded. Persist the tax calculation reference/version, jurisdiction, taxable basis, applied rate(s), exemption reference where applicable, amount, currency, timestamp and source. Protect sensitive exemption evidence and define failure behavior (block, estimate with explicit approval, or manual review) with tax/accounting counsel; never silently use stale tax rules as verified.

## 12. Subscriptions, rewards and financing

POS may initiate approved subscription enrollment/renewal, retrieve subscription status, apply eligible benefits, redeem rewards where authorized and present promotional offers according to current system rules. A subscription benefit is validated server-side against authoritative membership/price data.

Financing applications must be initiated through approved providers. Submission is not approval. Verify provider decision and authorized amount before treating it as a valid tender/financed sale. Store minimum provider reference/status and consent, not unnecessary financial application content. Keep Rewards Credit Card product distinct from MME in-house financing and from subscriptions; do not imply credit approval from rewards or membership status.

## 13. Returns, refunds and exchanges

Integrate Returns/Build 017 and Payments Center only after their service contracts and status are verified. Workflow: retrieve original transaction → verify purchase and item/unit → capture serial/IMEI only through authorized restricted flow when needed → complete required inspection → determine eligibility → obtain required approval → create refund/exchange request → provider processes original-method refund where supported → verify refund state → update inventory disposition separately → send Accounting references → create return receipt.

Refund controls include role limits, manager/CEO thresholds, original-tender policy, refund reference/state, reason and audit. Refund request does not mean refund complete. Do not refund more than eligible captured amount or create duplicate refunds. Inventory restock requires approved inspection/disposition and is never automatic solely because refund was requested. Exchanges are linked transactions with explicit stock and tender accounting.

## 14. Offline and network failure behavior

Show network, provider, terminal, printer and inventory freshness/status where available. Preserve cart contents only according to approved privacy/session policy; protect against local exposure and duplicate submission. A reconnect must retrieve authoritative transaction state before retrying an operation.

Do not finalize payment without verified authorization/capture state. Offline card acceptance is disabled unless provider, certified terminal, acquirer, risk limits, storage/forwarding and reconciliation policy explicitly support it and the exact implementation is tested. For connectivity loss, distinguish unsent, pending, unknown, failed and completed; direct ambiguous cases to reconciliation rather than charge again. Printer/drawer/network failure must not silently alter a valid sale state.

## 15. End-of-day and register reconciliation

Opening: cashier, register, store, opening cash, timestamp. During operations: sales by tender, refunds, voids, adds/removals, manager overrides and drawer events. Closing: expected and counted cash, variance, card/other tender totals, refunds, provider settlement status, closing balance, cashier attestation, manager verification and Accounting report reference.

Reconciliation compares POS transaction/tender records to Payments Center/provider, cash drawer and Accounting. Variances are exceptions with owner, explanation, review, correction reference and audit; completed close records cannot be silently edited. Define treatment for pending settlements, offline transactions, tips if any, taxes and store timezone. Cash variance does not automatically imply misconduct or disciplinary action.

## 16. Accounting, commissions, Build 005/006 integration

Accounting receives stable transaction ID, channel/location, gross/net sales basis, approved discounts, tax details, payment allocations, COGS reference, refunds, processor fees where available, settlement references and posting status according to Accounting’s contract. POS reports accepted/rejected/queued status and supports idempotent retry; it does not create independent journal policy or claim posted accounting before confirmation.

Commission Management receives sales attribution, eligible product/category/units, transaction and refund/return references. It applies the authoritative compensation configuration and adjustment rules. POS neither computes payroll nor authorizes commission payment.

Build 006 receives payment failure/discrepancy, drawer/printer failure, POS offline, inventory mismatch, duplicate attempt, unauthorized discount, approval-required refund, cash variance and settlement discrepancy events. Events are minimal, correlated, idempotent and route to authorized tasks/notifications. Notification failure does not alter transaction outcome.

## 17. Reporting and analytics

Authorized reports may include daily/weekly/monthly sales, employee and cashier attribution, category/product/store, tender method, average transaction value, discounts, returns/refunds, opening/closing cash, drawer variance, register activity and payment reconciliation. Define calculations and included statuses. Reports reconcile to source transaction records and distinguish pending/estimated/reconciled values.

Views may include accessible tables, charts, comparisons, transaction detail and exports. Identity Matrix permission scopes apply to records, employee comparisons, financial fields and exports. Audit sensitive drill-downs and exports. Never include full card data or PIN. Use Build 005 metric definitions where applicable; POS is not a source for accounting net income unless Accounting has confirmed it.

## 18. Security and payment compliance boundary

- Secure employee authentication, role/location/register authorization, MFA/step-up for privileged actions, session timeout/revocation and audit.
- TLS, secret management, environment separation, server-side price/tax/discount validation, CSRF/session protections as appropriate, input validation, rate limiting, secure error handling and monitoring.
- Use processor-hosted/validated payment components and certified terminal integrations. Minimize MME handling/storage of cardholder data to reduce scope; obtain a formal PCI DSS scope/requirements assessment with the acquiring bank/qualified assessor. This specification is not a PCI compliance attestation.
- Never store raw card numbers/PAN, CVV, PIN, track data or sensitive authentication data. Do not log them, render them in receipts or send them through GitHub.
- Verify provider webhooks, protect idempotency/replay, reconcile and maintain dispute/refund handling.
- Separate development/staging/live credentials and transaction data. Use provider test modes/synthetic records before authorized production testing.
- Audit sensitive payment/refund/discount/void/override/register-close/configuration actions with actor, reason, record reference and outcome.
- Keep restricted customer identifiers/employee details out of GitHub source, Issues, commits, Actions logs and artifacts.

## 19. GitHub development and deployment governance

Inspect repository settings, ownership and available plan features before claiming controls. Where approved and supported, configure protected production branch/rulesets, CODEOWNERS, required review/checks, restricted Actions permissions, isolated development/staging/production environments, required production deployment approvals, secret/dependency/code scanning, release versioning and migration validation.

Use least-privilege workflow tokens, review/pin third-party Actions where appropriate, and OIDC/short-lived credentials where the deployment provider supports it. GitHub Actions may run tests, validate migrations, scan code and deploy reviewed software under approved gates; it must not directly modify production transactions, payment records or inventory. Deployment approval is not business transaction authorization.

## 20. Implementation phases

1. **GitHub and system audit:** inspect existing application, providers, data, workflows, auth and current storefront behavior; verify actual Stripe account access, tax/provider, hardware and deployment configuration without exposing credentials.
2. **Interface foundation:** implement authenticated POS shell, register/session state, product lookup and cart using approved source APIs; preserve existing storefront.
3. **Transaction orchestration:** implement versioned transaction states, tax/discount validation, inventory reservation, idempotency, retries, exception queue and audit.
4. **Payments:** integrate Payments Center/provider in test mode; validate webhooks, state/reconciliation, declines, reversals, split tender and refunds. Qualify Verifone M425 separately before claiming support.
5. **Hardware and receipts:** test selected drawer/printer/terminal, central receipt settings, configurable validated QR, print failure and drawer-failure notifications.
6. **Enterprise integration:** connect verified CRM, Inventory, Commission, Accounting, Returns, Subscription/Rewards and Build 006 APIs with contracts and sandbox evidence.
7. **Production readiness:** accessibility, security, payment-compliance review, load/failure/recovery testing, controlled authorized live transaction and refund plan, reconciliation, rollback and operational signoff.

## 21. Acceptance criteria and verification plan

Build 009 is ready for production approval only when evidence demonstrates:

- [ ] Employees authenticate and POS server-side permissions restrict location/register, customer data, discounts, overrides, refunds, attribution and reports.
- [ ] Product search/barcode lookup uses catalog authority and does not expose protected serial/IMEI or authorize changes.
- [ ] Inventory availability and reservation are verified; concurrent checkouts prevent oversell; reservation remains distinct from sale.
- [ ] Customer lookup respects identity/CRM permissions and employee/customer relationship separation.
- [ ] Cashier and assisting representative attribution are distinct, auditable and connected to authoritative Commission rules.
- [ ] Tax is calculated through an approved source, stored with details and tested for jurisdiction/product classifications; no permanent hardcoded rate.
- [ ] Discounts apply only under active approved rules; price override attempts require authorization/approval and preserve original price.
- [ ] Cash and supported card/contactless transactions have independent authoritative status; client redirect/button is not accepted as proof.
- [ ] Stripe account and payment integration are verified; webhook signature/replay, idempotency, decline, reversal, timeout, refund and reconciliation tests pass in provider test mode.
- [ ] No raw PAN/card number, CVV, PIN, track data or sensitive authentication data is stored or emitted in MME OS, logs, receipts, source or GitHub.
- [ ] Split payments reconcile allocations and partial-failure recovery; remaining balance blocks full-payment status unless approved financing/receivable policy permits.
- [ ] Verifone M425 support is claimed only after exact device/processor certification and end-to-end testing; otherwise it is explicitly unavailable.
- [ ] Drawer failure leaves a completed sale/payment intact and creates authorized IT/management alert/task; printer failure does not reverse the sale.
- [ ] Receipt shows correct GM/cashier/representative details, approved versioned brand/store/policy content, safe payment references and tested configurable QR destination.
- [ ] Refund/return workflows validate original transaction, approval, processor result and independent inventory inspection/disposition; no duplicate refund or automatic restock.
- [ ] Accounting and Commission receive idempotent source events and report acknowledgements/exceptions; POS does not calculate payroll or claim unconfirmed posting.
- [ ] End-of-day opening/closing, cash count/variance, tender totals and settlement reconciliation are auditable; closed records cannot be silently edited.
- [ ] Offline/network failure distinguishes pending/unknown/failed/complete and never falsely reports payment success; no offline card mode without verified provider support.
- [ ] Build 006 alerts are durable, deduplicated and routed appropriately; notification delivery failure does not lose business records.
- [ ] Security, accessibility, responsive hardware UI, recovery, audit, permission and provider sandbox tests pass and are reviewed.
- [ ] Existing storefront remains intact; commit/release, environment, test evidence, reviewer, actual provider/hardware capabilities and known gaps are recorded.

Minimum negative tests: duplicate payment submission; forged/replayed webhook; payment pending shown as complete; stale/unauthorized price; parallel reservation oversell; barcode attempting price override; unauthorized customer lookup; cashier impersonating representative; unapproved discount; split-tender partial failure; drawer failure after capture; printer failure; refund retry duplication; POS offline with unknown payment; unauthorized register close edit; secret/card data in logs; and Actions attempting production transaction mutation.

A “real authorized live transaction” is a production acceptance gate that requires explicit authorization, approved test/customer handling, payment-provider and finance signoff, verified webhook and reconciliation, refund/rollback procedures, monitoring and evidence protection. Do not initiate live transactions merely to satisfy documentation or before those controls are ready.

## 22. Open decisions before implementation

1. POS application architecture, transaction database, order ownership and transaction state machine/commit point.
2. Existing Stripe account verification, product configuration, supported in-person and split-tender features, webhook ownership and reconciliation process.
3. Exact Verifone M425 model/firmware, processor/acquirer support, certified SDK/integration, PCI responsibilities and device network setup.
4. Tax provider, jurisdictions, product tax classifications, exemption handling and fail-safe behavior.
5. Cash, gift-card, financing, accounts-receivable and split-tender policies/providers.
6. POS hardware: registers, scanner, drawer, printer, operating systems, drivers, supported wired/wireless models and device-management method.
7. Store/location/register model, opening cash, manager override thresholds, cash procedures and separation of duties.
8. Discounts, pricing, attribution and commission contracts; refund/void thresholds and approval/segregation rules.
9. Receipt fields, store-specific configuration ownership, logo assets, return/warranty policy, review destination verification and promotional consent rules.
10. Offline policy, transaction recovery, RTO/RPO, queue/dead-letter ownership and incident response.
11. Returns/Build 017 status and interface; Accounting, CRM, Inventory, Subscription and Build 006 sandbox/API access.
12. Formal PCI DSS scope assessment, privacy/legal review, live testing controls and production operator ownership.

## 23. Current completion boundary

This file records the Build 009 POS architecture and acceptance specification only. No POS interface, transaction backend, tax service, Stripe integration, Verifone M425 certification, cash drawer, receipt printer, receipt settings, review QR, inventory reservation, CRM integration, refund workflow, accounting/commission synchronization, end-of-day reconciliation, or live payment capability is established or verified by this document. Build 009 must not be described as implemented or production-ready until additive implementation is tested in the actual deployment environment, providers/hardware are verified, acceptance criteria pass, and accountable operations, finance, security and payment stakeholders approve the evidence.
