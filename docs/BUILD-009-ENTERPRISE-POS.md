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

Build 009 specifies an enterprise POS for authorized retail employees to create sales, coordinate inventory reservations, process supported tenders, issue receipts, attribute sales, and synchronize authorized transaction references with accounting, commissions, CRM, returns, and reporting.

GitHub manages source, reviewed configuration, tests, migration validation and deployment. The MME OS backend owns POS transaction workflow records and coordinates authenticated calls to the authoritative modules. Payment providers remain authoritative for provider-side payment authorization, capture, refund and settlement state. POS must never store raw card numbers or CVV and must not treat a browser response, button click, or unverified terminal message as payment evidence.

This document is a target specification only. The repository currently contains a public storefront shell and placeholder routes; no POS, payments, tax, inventory, device, accounting, or commission integration is established or verified by this document. Inspect actual runtime, providers, data and settings before implementation. Preserve existing functionality and implement additively.

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

All external/module calls are authenticated, scoped, versioned and correlated. POS uses module APIs/events, not direct cross-module database writes. The implementation topology, database, hardware vendors, tax provider, deployment and operational objectives require reviewed implementation decisions.

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

Suggested left/catalog, center/cart, right/customer/totals arrangement is a design option, not a requirement that compromises mobile/tablet usability. All controls must be keyboard/touch accessible; status must not rely on color or animation alone.

### Employee permissions

Enforce Identity Matrix permissions on product lookup, customer data, discount application, price override request, attribution, cash actions, refund/void, register close, receipt access, exports and configuration. Managers may have explicitly scoped additional permissions. CEO governance and critical overrides require strong authentication, confirmation and audit. UI visibility alone is not authorization.

## 5. Product, cart and inventory flow

Product lookup may use barcode, SKU, product name, brand, model, category, or authorized serial lookup. Barcode/serial input identifies a record but never authorizes a price override, customer disclosure or inventory adjustment.

Display authorized product name, SKU, brand/model, condition, active approved price, availability, warranty and permitted specifications. Never expose IMEI/serial beyond explicitly authorized internal workflows.

### Transaction lifecycle

1. Authenticated cashier opens a register session and selects store/register.
2. POS retrieves current catalog, active price and permitted promotion versions.
3. Employee adds items and identifies customer/assisting representative when applicable.
4. POS validates quantity and requests inventory reservation using an idempotency key and expiry policy.
5. POS calculates the draft amount using approved discount and tax services; changes recalculate and preserve an audit trail where material.
6. Backend creates a payment request through Payments Center/provider; customer presents tender using approved components.
7. Payment authorization/capture status is confirmed by trusted server/provider response or verified webhook; uncertain outcomes remain pending/reconciliation-required.
8. POS finalizes a sale only under the approved order/payment policy. Inventory receives an idempotent commit/movement command tied to the authoritative transaction; uncompleted/expired orders release reservations according to policy.
9. Receipt is generated from verified transaction/payment/tax data and versioned settings.
10. Commission and Accounting receive source references/events; each acknowledges or enters an exception queue.
11. POS provides an auditable completion summary and notifies the customer through an approved channel.

A declined, pending, cancelled, partial or unknown payment must not be presented as a completed fully paid sale. Inventory reservations are not sales. A client-side button, redirect, terminal UI alone, or stale cached state is not proof of completion. Multi-step failure uses durable pending states and reconciliation rather than false success or duplicate charge/deduction.

## 6. Customer identification and sales attribution

Integrate Build 007 CRM and Build 004 identity rules. Support permitted lookup by verified email/phone/customer ID, account verification, new customer handoff, authorized purchase history, subscription/rewards status and representative association. Collect minimum necessary customer data; caller ID or barcode is not proof of identity.

Record transaction ID, cashier, assisting representative(s), supervising manager where applicable, store/register, transaction time, channel and attribution history. The employee helping the customer may differ from the cashier. Attribution changes require permission, reason, audit history and any approval. Commission eligibility follows authoritative Commission Management policy. Customer access remains independent of employee status.

## 7. Tender and payment processing

### Supported tender types

Subject to provider, policy, legal and operational verification: credit/debit card, contactless, cash, approved gift card, approved financing, split tender and other explicitly authorized methods. Enable only methods supported by selected providers/hardware and approved for the store/jurisdiction.

### Stripe/Payments Center contract

Connect to the existing MME Stripe account only after account ownership, API credentials, enabled products, terminal capability, environment, webhook endpoint and refund/reconciliation processes are verified.

Requirements:

- Server-created payment requests derived from trusted cart/pricing/tax values.
- Idempotency keys bound to transaction and operation; distinct keys for authorize/capture/refund where required.
- Verify webhook signatures against raw request body; deduplicate events and validate object/account/environment before state transition.
- Treat browser/terminal client results as untrusted until server/provider confirmation.
- Handle decline, timeout, reversal, partial capture, duplicate/replayed event, delayed webhook and provider outage.
- Reconcile processor records to POS orders, tenders, refunds, settlements and Accounting; preserve exception queues and correction evidence.
- Store minimum necessary provider references/status and timestamps. Never store raw PAN, CVV, PIN, track data or sensitive authentication data.
- Keep test/live credentials separate and secret-managed. Do not expose payment secrets in browser code, source, Actions logs or artifacts.

### Split tender and balance

Represent transaction total, each tender allocation, approved financing/receivable amount, amount paid, remaining balance and tender status with currency precision. Validate sum of accepted allocations and provider-confirmed amounts; support partial tender failure and safe recovery without recharging a successful tender. Do not mark the sale fully paid while a balance remains unless an explicitly approved financing/accounts-receivable policy allows it.

## 8. Verifone M425 terminal qualification

The specified Verifone M425 is an unverified target until exact hardware, firmware, payment processor/acquirer, certification, SDK/connector and deployment compatibility are confirmed. Do not assume every Stripe Terminal configuration supports the M425.

Before production: confirm selected processor/acquirer and certified integration; verify model/firmware and supported methods; establish secure pairing/network and device ownership; test authorization/capture, declines, reversals/voids, refunds, duplicate/replay, disconnect mid-transaction, recovery and settlement reconciliation. Protect terminal credentials and prevent card data from entering MME logs or application storage. If compatibility is not verified, disable the method and state that it is unavailable.

## 9. Cash, registers, drawers and receipts

### Register/cash drawer lifecycle

A register session records cashier, register/location, opening cash/time, cash sales/refunds, additions/removals, authorized no-sale/manual opens, expected closing cash, actual count, variance, manager verification and close. Enforce role permissions, reason/approval policy, immutable history and separation of duties where feasible.

Drawer commands and sale/payment states are separate. On successful sale with drawer failure: preserve sale and payment status; create a hardware failure event; alert IT and store management through Build 006; create an assigned task; use only authorized manual procedures; verify repair and document closure. Drawer failure must not reverse or retry a successful payment.

### Receipt printer and delivery

Support selected compatible thermal printers after device testing: automatic print, authorized reprint, customer/store copy, digital receipt, printer status and failure notification. Print failure does not reverse a transaction. Reprint must not recreate payment or sale and records actor/reason.

### Configurable receipt system

Company-managed, versioned settings may include approved MME logo; store address/phone; transaction date/time/timezone/ID; General Manager where configured; cashier and assisting representative clearly distinguished; product/SKU/quantity/condition/prices/discounts; subtotal/tax/total; safe payment method/reference; return policy and applicable warranty; approved promotions and footer. Receipt data comes from finalized transaction and current approved policy/template versions. Do not expose card credentials or internal IMEI/serial. CEO/company administrators govern company-wide standards.

### Review QR code

A configurable customer review QR may be enabled when an approved landing page is provided. Authorized management may update the URL through validated settings; receipt preview reflects the active version. Validate destination format/approval and test generated code on actual printed output and smartphones before use. Do not encode customer-specific tracking or personal information without approved consent/privacy policy.

Promotional messages about subscriptions, memberships, rewards and offers are versioned, approved and subject to applicable marketing/receipt policy. Keep MME Rewards Credit Card information separate from MME in-house financing.

## 10. Discounts, promotions and price integrity

Support fixed, percentage, category, product, subscription/membership, manager-approved and CEO-approved discounts only when configured by Pricing/Marketing policy. Each application validates eligibility, date, product/category, combination rules, amount and actor permission. Thresholds, approval levels, promotional codes, expiration and audit history are required.

Preserve original approved price version, discount rule/amount, approver, reason, final unit price and transaction calculation. Unauthorized discount attempts are rejected and may generate an audited event. Employees cannot change authoritative product selling price; override requests route through the owning approval workflow. Preserve enough detail for returns, tax and Accounting reconciliation.

## 11. Tax calculation

Tax is calculated for applicable jurisdictions using transaction location, product tax classification and legally relevant customer/transaction facts through an approved tax service/source. Rates and rules must be maintained through an approved provider or controlled process, never a permanent hardcoded rate.

Store jurisdiction, taxable basis, product classification, rate/source/version, exemption evidence reference where permitted, calculation timestamp, rounding, line and total amounts, and provider response/reference for audit. Define tax treatment for discounts, returns, shipping, pickup, voids, split tenders and exemptions with tax/accounting review. Tax provider failure follows an approved fail-safe policy; do not silently use fabricated or stale rates.

## 12. Subscriptions, rewards and financing

POS may initiate approved subscription enrollment/renewal, retrieve subscription status, apply eligible benefits, redeem rewards where authorized and present promotional offers according to current source rules. Record the entitlement/version and resulting discount reference. MME Rewards Credit Card programs are separate from rewards redemption, subscriptions and in-house financing.

Financing applications must be initiated through approved providers. Submission is not approval. Verify provider decision and authorized amount before treating it as valid tender/financed sale; store minimal provider reference/status and reconcile. Never infer approval or terms from customer profile or AI output.

## 13. Returns, refunds and exchanges

Integrate Returns/Build 017 and Payments Center only after their service contracts/status are verified. Workflow: retrieve original transaction → verify purchase and item/unit → capture serial/IMEI only through authorized restricted flow → inspect condition → determine eligibility → obtain approval → process refund/exchange through provider and source service → update Inventory only from authorized disposition → update Accounting → generate linked return receipt.

Refund controls include role limits, manager/CEO thresholds, original-tender policy, refund reference/state, reason and audit. Refund request does not mean refund complete. Do not refund more than permitted against original captured balance; handle partial refunds and provider-specific constraints. Refund, return status, inventory disposition and settlement are separate states. A returned item is not available until inspection and Inventory approval. Exchanges link original and replacement transactions with amount/tax/payment reconciliation.

## 14. Offline and network failure behavior

Show network, provider, terminal, printer and inventory freshness/status where available. Preserve cart contents only according to approved privacy/session policy; protect against local exposure and do not persist payment credentials. Prevent duplicate checkout with transaction/idempotency references.

Do not finalize payment without verified authorization/capture state. Offline card acceptance is disabled unless provider, certified terminal, acquirer, risk limits, storage/forwarding and reconciliation controls explicitly support it and are approved. If network fails during payment, mark unknown/pending and reconcile by provider reference before retrying; never blindly resubmit. Document safe outage and recovery procedures for POS, tax, inventory, payment and hardware.

## 15. End-of-day and register reconciliation

Opening records cashier, register, store, opening cash and timestamp. During operations record sales by tender, refunds, voids, cash adds/removals, manager overrides and drawer events. Closing records expected and counted cash, variance, tender totals, refunds, settlement status, drawer balance, cashier attestation, manager verification and close time.

Reconciliation compares POS transaction/tender records to Payments Center/provider, cash drawer and Accounting. Variances are exceptions with owner, explanation, review, correction reference and history. Completed close records cannot be silently edited; corrections use a permissioned, reasoned and audited adjustment/reopen workflow. Pending settlement is not settlement complete.

## 16. Accounting, commissions, Build 005/006 integration

Accounting receives stable transaction ID/version, channel/location, gross/net sales basis, approved discounts, tax details, payment allocations, COGS reference, refunds, processor fees where available, settlement references and posting status. Accounting owns journal mapping/posting; POS records acknowledgement and exceptions without creating a competing ledger.

Commission Management receives sales attribution, eligible product/category/units, transaction and refund/return references. It applies authoritative compensation configuration and adjustment rules. POS must not calculate payroll or authorize commissions.

Build 006 receives payment failure/discrepancy, drawer/printer failure, POS offline, inventory mismatch, duplicate attempt, unauthorized discount, approval-required refund, cash variance and settlement discrepancy events. Use stable IDs, correlation and idempotency; notification/task delivery failure does not delete or alter transaction records.

## 17. Reporting and analytics

Authorized reports may include daily/weekly/monthly sales, employee and cashier attribution, category/product/store, tender method, average transaction value, discounts, returns/refunds, opening/closing cash, variance, register activity and payment reconciliation. Views may include accessible tables, charts, comparisons, transaction detail and exports.

Identity Matrix scope applies to records, employee comparisons, financial fields and exports. Each report identifies source, definition, currency/timezone, period, freshness and actual/pending/estimated status. Reconcile results to underlying records; do not silently replace unavailable data with zero. Audit sensitive exports.

## 18. Security and payment compliance boundary

- Secure employee authentication, role/location/register authorization, MFA/step-up for privileged actions, session timeout/revocation and audit.
- TLS, secret management, environment separation, server-side price/tax/discount validation, CSRF/session protections as appropriate, input validation, rate limiting, secure error handling and monitoring.
- Use processor-hosted/validated payment components and certified terminal integrations. Minimize MME handling/storage of cardholder data to reduce scope; obtain formal PCI DSS scope/requirements guidance before production.
- Never store raw card numbers/PAN, CVV, PIN, track data or sensitive authentication data. Do not log them, render them in receipts or send them through GitHub.
- Verify provider webhooks, protect idempotency/replay, reconcile and maintain dispute/refund handling.
- Separate development/staging/live credentials and transaction data. Use provider test modes/synthetic records before authorized production testing.
- Audit sensitive payment/refund/discount/void/override/register-close/configuration actions with actor, reason, record reference and outcome.
- Keep restricted customer identifiers/employee details out of GitHub source, Issues, commits, Actions logs and artifacts.

PCI DSS-aligned design is not a compliance certification or legal determination. Provider, acquirer and qualified security guidance must determine actual obligations.

## 19. GitHub development and deployment governance

Inspect repository settings, ownership and available plan features before claiming controls. Where approved and supported, configure protected production branch/rulesets, CODEOWNERS, required reviews/checks, restricted Actions permissions, migration validation, dependency/secret/code scanning, release versioning and development/staging/production environments with production approval.

Use least-privilege workflow tokens, review/pin third-party Actions where appropriate, and OIDC/short-lived credentials where the deployment provider supports it. GitHub Actions may run tests, validate migrations, security checks and approved gated deployment; it must not directly modify production transactions, payment records, inventory or registers. Actions logs/artifacts contain no cardholder or confidential customer data. Deployment approval is not business transaction approval.

## 20. Implementation phases

1. **GitHub and system audit:** inspect existing application, providers, data, workflows, auth and current storefront behavior; verify actual Stripe account access, tax/provider, hardware and dependencies. Document gaps and preservation plan.
2. **Interface foundation:** implement authenticated POS shell, register/session state, product lookup and cart using approved source APIs; preserve existing storefront.
3. **Transaction orchestration:** implement versioned transaction states, tax/discount validation, inventory reservation, idempotency, retries, exception queue and audit.
4. **Payments:** integrate Payments Center/provider in test mode; validate webhooks, state/reconciliation, declines, reversals, split tender and refunds. Qualify Verifone M425 separately before enabling.
5. **Hardware and receipts:** test selected drawer/printer/terminal, central receipt settings, configurable validated QR, print failure and drawer-failure notifications.
6. **Enterprise integration:** connect verified CRM, Inventory, Commission, Accounting, Returns, Subscription/Rewards and Build 006 APIs with contracts and sandbox evidence.
7. **Production readiness:** accessibility, security/payment-compliance review, load/failure/recovery testing, controlled authorized live transaction and refund plan, reconciliation, rollback and operational sign-off.

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

Minimum negative tests: duplicate payment submission; forged/replayed webhook; payment pending shown as complete; stale/unauthorized price; parallel reservation oversell; barcode attempting price override; unauthorized customer lookup/refund/manual drawer open; split tender partial failure; M425 unverified; successful payment with drawer failure; printer failure/reprint; network loss after authorization; tax provider outage; promotion opt-out; modified quote using stale price; refund exceeding captured amount; return auto-restock; unauthorized register-close edit; and sensitive data in logs/receipt/export.

A “real authorized live transaction” is a production acceptance gate that requires explicit authorization, approved transaction/customer handling, payment-provider and finance signoff, verified webhook/reconciliation/refund procedure, and responsible operator. Do not conduct live payment tests without that plan.

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

This file records the Build 009 POS architecture and acceptance specification only. No POS interface, transaction backend, tax service, Stripe integration, Verifone M425 certification, cash drawer/printer integration, receipt configuration/QR, financing, split tender, end-of-day close, return/refund process, accounting/commission integration or production security control is established or verified by this document. Do not claim Build 009 is implemented or production-ready until additive implementation is tested, providers/hardware are verified, authorized production transaction/refund/reconciliation evidence is reviewed, and accountable operations, finance and security owners sign off.
