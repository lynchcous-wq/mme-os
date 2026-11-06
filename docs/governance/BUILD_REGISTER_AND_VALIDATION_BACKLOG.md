# MME OS Build Register & Validation Backlog

**Status:** Governance draft; additive-only; not yet approved as the canonical numbering authority.  
**Repository:** `lynchcous-wq/mme-os`  
**Prepared:** 2026-11-06

## Purpose

This register separates three facts that must not be conflated:

1. **Branch exists** — a Git branch with the build identifier was found.
2. **Implementation verified** — the relevant files and behavior were inspected.
3. **Validated / production live** — automated and integration tests pass, migrations are applied, workers and credentials are configured, and the feature is verified in the target environment.

A branch name alone is not proof that a build is complete. This register does not certify any build as production-ready.

## Numbering governance — unresolved conflict

The repository README describes the current milestone as an initial responsive storefront shell and lists future milestones for catalog, identity, checkout, integrations, security, and analytics. It does not define the numbered architecture roadmap.

Earlier MME architecture planning assigned Build 009 to Product Catalog and Build 010 to Inventory. The implementation branch families currently use 009 for POS/commerce/warranty operations and 010 for security intelligence and notification operations.

**Decision required:** Joshua / project owner must approve one canonical mapping before branches are renamed, merged into a numbered release train, or the master roadmap is rewritten. Until then:

- Preserve all existing branch names and commit history.
- Treat the labels below as the *implementation branch stream*, not the canonical enterprise architecture numbering.
- Do not silently renumber builds or imply that branch sequence overrides the approved roadmap.
- Keep the default branch unchanged until a reviewed pull request is approved.

## Branch inventory snapshot

### Implementation stream 009 — POS, commerce, inventory and warranty

GitHub branch search found the sequence **009.20 through 009.99** (80 branches).

| Range | Branch workstream represented by the branch inventory |
|---|---|
| 009.20–009.27 | POS hardware dispatch, acknowledgments, device health/fleet, firmware, secure network, disaster recovery and POS security |
| 009.28–009.37 | Fraud, chargebacks, settlement, financial close/reporting, source connectors and financial synchronization |
| 009.38–009.46 | Inventory/COGS adapters, serialized checkout and returns, Stripe refunds, settlement and financial intelligence |
| 009.47–009.53 | Financial command center, alerts/notifications, customer communications, order automation/self-service and returns |
| 009.54–009.63 | Inventory recovery/pricing/research, purchasing, receiving, ledger, transfers, allocation, fulfillment and reverse logistics |
| 009.64–009.74 | Warranty repair, customer communications, financial/fraud intelligence, provider integrations, lifecycle, portal, analytics and notifications |
| 009.75–009.85 | Warranty renewal/claims, evidence upload/scanning, retention, compliance, APIs and audit/rate-limit controls |
| 009.86–009.99 | Warranty security monitoring/detection/escalation, executive cockpit, investigations, evidence integrity/retention, compliance, AI risk, anomaly detection, real-time alerting and delivery/failover |

This is a branch-name inventory. Each individual branch still requires file-level review and validation evidence.

### Implementation stream 010 — security intelligence and notifications

GitHub branch search found these branches:

| Build | Branch name suffix / scope |
|---|---|
| 010.00 | warranty-security-operations-dashboard |
| 010.01 | warranty-security-incident-case-management |
| 010.02 | warranty-security-evidence-vault-retention |
| 010.03 | warranty-security-intelligence-threat-detection |
| 010.03 extension | warranty-security-retention-execution-and-malware-scanning |
| 010.04 | cross-system-security-signal-ingestion-correlation |
| 010.05 | security-event-reliability-retry-dead-letter |
| 010.06 | security-event-source-adapters-provider-health |
| 010.07 | security-provider-failover-circuit-breakers |
| 010.08 | security-integration-observability-alerting |
| 010.09 | security-incident-escalation-case-management |
| 010.10 | security-incident-escalation-automation |
| 010.11 | security-notification-delivery-acknowledgement |
| 010.12 | notification-provider-adapters-retry-orchestration |
| 010.13 | notification-provider-failover-health-monitoring |
| 010.14 | notification-outage-alerting-provider-performance-analytics |
| 010.15 | notification-escalation-policy-executive-alerts |
| 010.16 | notification-policy-configuration-outage-automation |

**Note:** 010.03 has two separate branch names. Do not collapse them or change their identifiers without an approved crosswalk.

### Subsequent 010 branches already present

These branches were also found in GitHub. They are queued for inspection; their presence does not establish completion.

- 010.17 — notification-delivery-dispatch-and-channel-adapters
- 010.18 — notification-provider-receipts-delivery-reconciliation
- 010.19 — human-acknowledgement-escalation-sla-v2
- 010.19 — notification-human-acknowledgement-escalation-sla
- 010.20 — notification-escalation-dispatch-ownership-routing
- 010.21 — notification-escalation-scheduler-live-worker
- 010.22 — notification-escalation-per-channel-reconciliation
- 010.23 — notification-provider-receipt-webhooks-reconciliation
- 010.24 — notification-webhook-signature-hardening-replay-protection

**Duplicate identifier warning:** Two different 010.19 branches exist. Retain both until a reviewed crosswalk identifies whether one is a revision, alternate implementation, or separate scope.

## Completion and validation ledger

Use these status values consistently:

- **Branch found** — branch exists; code not yet reviewed.
- **Code reviewed** — implementation files inspected; not necessarily complete.
- **Tests passed** — relevant automated tests executed successfully with recorded output.
- **Migration applied** — migration applied to the intended Supabase environment and schema verified.
- **Integrated** — upstream/downstream APIs, credentials, provider connections, and worker scheduling verified.
- **Production verified** — end-to-end acceptance evidence exists in production.
- **Blocked** — dependency, defect, missing configuration, or decision prevents acceptance.

### Known review state from the recent Build 010 sessions

| Build | Review state | Known follow-up |
|---|---|---|
| 010.05 | Code files reviewed; tests not executed | Execute tests, apply migration, verify worker and retry/dead-letter behavior |
| 010.06 | Code files reviewed; tests not executed | Fix cumulative accepted/failure counters; add independent heartbeat checks; apply migration and verify provider credentials |
| 010.09 | Branch and implementation reported; runtime tests not verified | Verify incident creation, evidence links, audit events and authorization |
| 010.10 | Worker endpoint committed; tests/migration not verified | Validate SQL RPC contracts, schedule worker, test retry/terminal failure |
| 010.11 | Delivery worker committed; external provider delivery incomplete | Recover abandoned claims; connect providers; verify delivery and human acknowledgment |
| 010.12 | Provider dispatch worker committed; tests/migration not verified | Enforce provider circuit state; verify retry, receipt and quarantine RPCs |
| 010.13 | Existing provider health/failover branch reviewed; integration incomplete | Add scheduled probes; enforce circuit-breaker selection in actual dispatch |
| 010.14 | Provider monitor endpoint committed; tests/migration not verified | Schedule probes; connect outage alerts; validate recovery and SLA analytics |
| 010.15 | Default policy seed committed; tests/migration not verified | Add/verify scheduled escalation worker; validate policy SQL and delivery |
| 010.16 | Migration quoting correction committed; tests not executed | Run test script; apply migration; verify outage automation and policy approval |

**Important:** This table reflects the recorded work/review notes available during preparation. It is not a substitute for a fresh checkout, test run, migration inspection, or deployment check. No row above is certified as production verified.

## Required validation backlog

### P0 — Establish trustworthy build status

- [ ] Create a build-by-build evidence record: branch, commit SHA, changed files, tests executed, output, migration status, deployment status and blockers.
- [ ] Inspect all recent 009 and 010 branches for uncommitted dependencies and missing integration points.
- [ ] Run the repository's actual test/lint/build commands in a controlled CI environment; do not infer tests from package scripts.
- [ ] Verify every migration against a clean database and an upgrade path from the current schema.
- [ ] Verify RLS, grants, service-role boundaries, authentication and role authorization.
- [ ] Verify idempotency, duplicate events, concurrency/leases, retry exhaustion, dead-letter replay and audit immutability.
- [ ] Add end-to-end tests for critical checkout, refund, inventory, warranty and security workflows.
- [ ] Record environment-specific secrets/configuration by name only; never commit secret values.

### P1 — Repair known cross-build gaps

- [ ] 010.06: make health counters cumulative and implement independent heartbeat monitoring.
- [ ] 010.09/010.10: verify incident lifecycle, escalation SLA clock, scheduler, retry and terminal-state transitions.
- [ ] 010.11/010.12: reconcile delivery-worker ownership and queue claim contracts; recover expired claims safely.
- [ ] 010.12/010.13: make dispatch select only eligible providers and enforce circuit-breaker state at send time.
- [ ] 010.13/010.14: implement scheduled probes, outage open/recovery transitions and notification fan-out.
- [ ] 010.15/010.16: verify policy precedence, policy versioning, CEO approval, escalation scheduler and recovery behavior.
- [ ] 009.42–009.46: validate Stripe refund/settlement idempotency and reconciliation end to end.
- [ ] 009.58–009.63: validate inventory receiving, ledger posting, transfer, allocation and fulfillment consistency.
- [ ] 009.64–009.85: validate warranty lifecycle, evidence retention, privacy access, and compliance workflows.
- [ ] 009.86–009.99: validate detection-to-case-to-evidence-to-alert-to-delivery flow.

### P2 — Release readiness

- [ ] Define staging and production environments and migration promotion procedure.
- [ ] Configure scheduled workers, timeouts, concurrency limits, health checks and alerting.
- [ ] Verify backup/restore, disaster recovery and rollback procedures.
- [ ] Establish observability dashboards and operational runbooks.
- [ ] Conduct security review and role-based acceptance testing.
- [ ] Obtain owner approval for the canonical build-number crosswalk.
- [ ] Merge only reviewed pull requests; do not merge directly to the default branch as part of this governance draft.

## Standard acceptance checklist for every build

A build cannot be marked **Complete** until all applicable checks are evidenced:

1. Scope and dependencies match the approved build specification.
2. Changes are additive and do not regress prior workflows.
3. Automated unit/integration tests pass.
4. Type check, lint and production build pass.
5. Database migrations apply cleanly and are reversible or have a documented forward-recovery plan.
6. RLS, least privilege, input validation, rate limits and audit events are verified.
7. Retry, idempotency, concurrency and failure recovery are tested.
8. UI permissions, empty/error/loading states and accessibility are checked.
9. External provider credentials and webhook signatures are verified in staging.
10. End-to-end acceptance evidence is recorded.
11. Deployment is verified before labeling the feature production live.

## Next implementation sequence

1. Keep **010.17 — Notification Delivery Dispatch & Channel Adapters** as the next branch to inspect and implement.
2. Before marking it complete, reconcile its dispatch contract with 010.11–010.16 and the provider health/circuit-breaker APIs.
3. Work through P0 validation in parallel, prioritizing security, payments, inventory ledger and worker reliability.
4. Resolve the canonical 009/010 numbering crosswalk with the project owner before changing labels or branch history.


---

## Launch-readiness audit — 2026-11-06

**Overall assessment: NOT READY FOR LIVE CUSTOMER LAUNCH.** This is based on a direct comparison of the repository default branch (`main`) and the Build 010.17 implementation branch, plus inspection of the public routes, package manifest, Build 010.17 worker, migration, and CI logs.

### P0 — Default branch is still a storefront prototype

The default branch README explicitly describes the app as an initial storefront shell and states that there is no live catalog, account system, checkout, Stripe connection, or inventory integration. Direct inspection confirms:

- `app/products/page.tsx` displays a “catalog is being prepared” placeholder.
- `app/account/page.tsx` displays “Coming soon” and says customer accounts are part of a future build.
- No `app/login/page.tsx`, `app/cart/page.tsx`, `app/checkout/page.tsx`, `app/api/checkout/route.ts`, or `app/api/stripe/webhook/route.ts` was found on the inspected Build 010.17 branch at those paths.
- The default `package.json` contains only Next.js, React and React DOM runtime dependencies and only dev/build/start/type-check scripts.
- The public home page contains hard-coded illustrative product names and prices; it is not a database-backed live catalog.

**Launch consequence:** Do not advertise the current default-branch site as a functioning store or accept customer payments through it.

### P0 — Build branch integration is not release-safe

Commit comparison reports the Build 010.17 branch as **1,004 commits ahead and 24 commits behind `main`**; the compare response is capped at 300 changed files. This is a substantial divergence, not a small feature branch.

The shared foundation branch `implementation-foundation-001-009` compares as zero commits ahead and 22 behind `main`, with no changed files in that comparison. This is not evidence that all Build 001–009 modules have been integrated into the default branch.

**Required:** inventory pull requests and commit ancestry; map each build's migrations, routes, libraries, tests and dependencies; reconcile the 24-commit divergence; integrate in reviewed, testable slices. Do not merge the full 010.17 branch into `main` blindly.

### P0 — Build 010.17 CI has a recorded failure

The Build 010.17 workflow run (PR 113) installed dependencies successfully, then failed at `npm run lint` (`tsc --noEmit`). The failure was caused by inherited syntax errors in:

- `app/api/internal/security-event-adapters/route.ts`
- `app/api/internal/warranty-security-evidence-scan/route.ts`

The notification-specific test step was skipped because lint failed. Two syntax corrections were subsequently committed to the Build 010.17 branch, but a successful rerun has not been observed. The PR's Vercel deployment status was also reported as failure. Do not treat the later commits as validated until CI reruns successfully.

### P0 — Customer checkout and identity are not live on the release branch

No evidence was found on the inspected release branch that the public storefront is wired to:
- Supabase-backed catalog reads and stock reservations,
- customer registration/login/session recovery and account ownership,
- employee/CEO role separation on the public app,
- cart and order creation,
- tax, shipping and local-pickup selection,
- Stripe checkout session creation and signed webhook reconciliation,
- refunds/chargebacks tied to a real order ledger.

Some related internal implementation branches and APIs exist, but they are not exposed by the current public product/account routes. These capabilities must be integrated and acceptance-tested before launch.

### P1 — Build 010.17 provider delivery is not production proven

The Build 010.17 documentation explicitly states that no provider credentials were supplied or tested, no actual messages were sent, provider callbacks/receipts are not implemented in this build, and a protected worker schedule remains to be configured.

Code inspection also identified release-hardening points:
- The pager/push webhook adapter signs payloads but does not itself enforce HTTPS on the configured URL.
- SendGrid/Twilio/Telnyx delivery idempotency and uncertain-timeout duplicate behavior need provider-specific verification; do not assume the local delivery ID guarantees external exactly-once delivery.
- Provider acceptance is not final recipient delivery; receipt callbacks and reconciliation remain necessary.
- Role-to-recipient environment mappings need real owner-approved destinations and a safe test procedure.

### P1 — Build numbering and scope require reconciliation

Branch searches found:
- Build 001-related branches and a shared `implementation-foundation-001-009` branch.
- No matching branch result for Build 002 or Build 006.
- Build 003, 004, 005, 007 and 008 branches.
- Implementation stream 009.20–009.99 and 010.00–010.24.
- Duplicate identifiers 010.03 and 010.19 across distinct branches.

The previously approved architecture map assigned 009 to Product Catalog and 010 to Inventory, while the current 009/010 branch families represent POS/commerce/warranty and security/notification work. Owner approval of a canonical crosswalk remains required. Do not silently rename branches.

### Release gates — must all pass

- [ ] Identify the intended release branch and confirm it contains the complete, reviewed integration of Builds 001–010.17.
- [ ] Reconcile main/feature branch divergence without losing existing changes.
- [ ] Make the public catalog database-backed; remove all sample/illustrative prices from customer purchase flows.
- [ ] Complete customer sign-in, employee sign-in, role separation, account recovery and authorization tests.
- [ ] Complete cart, order, tax, shipping/local pickup and Stripe checkout/webhook/reconciliation workflows in Stripe test mode.
- [ ] Validate inventory reservation, serialized-device/IMEI controls, COGS, refunds, returns and warranty state transitions.
- [ ] Apply every migration to a clean staging database and upgrade a representative existing database; verify RLS, grants and service-role boundaries.
- [ ] Run all relevant build tests, full TypeScript check, lint and production build; record passing commit SHA and logs.
- [ ] Configure and verify all worker schedules, secrets, provider endpoints, webhook signatures, retry recovery and dead-letter operations.
- [ ] Complete end-to-end customer, employee, manager, CEO and operations acceptance testing.
- [ ] Verify domain/DNS, TLS, environment variables, backups, monitoring, rollback and Vercel production deployment.
- [ ] Obtain explicit owner approval for production cutover and a controlled first live transaction/refund.

### Immediate work order

1. Stabilize the Build 010.17 branch: rerun CI after the syntax fixes, fix all type/lint/build/test failures, and harden provider transport/receipt handling.
2. Build an evidence-based migration and module inventory across 001–010.17; separate implemented, branch-only, merged, tested, migrated, configured and production-verified states.
3. Integrate the foundational identity/catalog/checkout capabilities into a dedicated release branch in dependency order; do not deploy the current `main` storefront as a live store.
4. Complete staging acceptance, then production readiness and cutover.

**No production deployment, Supabase migration application, live Stripe transaction, or live notification provider delivery is certified by this audit.**


## Foundation integration deep dive — 2026-11-06

### Pull-request and dependency facts verified

The following open draft PRs were inspected directly; none is merged:

| PR | Scope | Base → head | State |
|---|---|---|---|
| [#8](https://github.com/lynchcous-wq/mme-os/pull/8) | Build 001 storefront catalog/demo bag + dependency lock/security | `foundation/repository-safeguards-ci` → `security/build-001-dependency-lockfile` | Open draft; CI status not present on inspected head |
| [#11](https://github.com/lynchcous-wq/mme-os/pull/11) | Build 001 atomic order creation/inventory reservations | `main` → `feature/build-001-inventory-order-schema-v2` | Open draft; Vercel checks succeeded on inspected head; not equivalent to full app/DB CI |
| [#12](https://github.com/lynchcous-wq/mme-os/pull/12) | Product catalog database + employee catalog workspace | `main` → `feature/product-catalog-foundation` | Open draft; earlier CI passed on inspected head |
| [#13](https://github.com/lynchcous-wq/mme-os/pull/13) | Build 001 catalog/inventory integration | `main` → `integration/build001-catalog-inventory` | Open draft; inspected Vercel checks failed due build-rate-limit/upgrade response; no Actions run surfaced for inspected head |
| [#14](https://github.com/lynchcous-wq/mme-os/pull/14) | Build 004 identity integration validation on PR #13 | `integration/build001-catalog-inventory` → `integration/build004-identity-validation` | Open draft; GitHub Actions passed on head `704205744b0f997df7adf7c8440a16fd0e4b45c0` |
| [#15](https://github.com/lynchcous-wq/mme-os/pull/15) | Authenticated checkout UI + Stripe Elements | `integration/build001-catalog-inventory` → `implementation/build001-authenticated-checkout-ui` | Open draft; Actions failed only at a stale webhook contract assertion; TypeScript/build steps were skipped |

PR #14's successful Actions run is specifically documented as:
- Fresh local Supabase startup and complete migration replay on an empty local DB.
- Full pgTAP suite: 93 files / 921 tests.
- Live local Supabase Auth + Build 004 authorization integration.
- TypeScript and Next.js production build.
- Supabase Edge Function type-check.

The successful run was on the earlier reported tested commit `e06c944c1f275f801cd8e82c670386ae144232d8`; PR #14's current head is `704205744b0f997df7adf7c8440a16fd0e4b45c0`, whose Actions run also completed successfully. It remains a draft and has not been deployed to the user's Supabase project.

### Build 001 checkout test correction committed

PR #15 CI log showed five of six checkout contract tests passing. The remaining test asserted that the webhook called the obsolete RPC name `mme_process_verified_payment_event`, while the inspected webhook actually verifies the Stripe signature and calls `mme_process_unified_order_payment_event`. This was a stale test expectation, not a reason to change the secure webhook implementation.

Updated `tests/build001-checkout-ui.contract.test.mjs` on branch `implementation/build001-authenticated-checkout-ui`:
- Assert the current unified payment-event RPC.
- Retain the refund-event assertion.
- Explicitly assert Stripe signature verification occurs before payment ledger processing.

Commit: `8928281c83805b84e49a0809ea466abab9ecaf6f`.

**Validation pending:** a new GitHub Actions run for this commit had not yet appeared at the time of this update. Do not mark PR #15 green until it runs and all jobs pass.

### Additional blockers surfaced

- The catalog/employee workspace PR #12 has substantial application, API, migration and test scope, but must be reconciled with the Build 004 identity model before its employee access routes are accepted.
- PR #13 is the intended Build 001 catalog/inventory integration checkpoint, but it is draft and its inspected Vercel checks were blocked by the account's Vercel build-rate-limit/upgrade response. That is a deployment-provider limitation, not proof that the application code failed.
- PR #14 depends on PR #13 and introduces identity/authorization compatibility reports and tests. It should not be merged independently of its base integration.
- PR #15 depends on PR #13. Its checkout UI uses Supabase Auth, Stripe Elements, the Edge Function `create-checkout-payment`, and signed webhook processing. Actual Stripe test-mode transactions and provider-side reconciliation remain unverified.
- Branch names alone are insufficient to map Builds 002, 003, 006. Repository PR searches did not identify authoritative standalone PRs for each. Resolve the architecture crosswalk rather than inventing missing implementation.

### Safe next integration order

1. Re-run and complete PR #15 CI after the stale test correction.
2. Resolve the Vercel build-rate-limit issue or use a verified alternative preview/build path; do not bypass failed required checks.
3. Reconcile PR #8, #12, #13 and #11 for duplicate migrations, schema ownership, package manifests, shared components, and migration timestamp ordering.
4. Keep PR #14 dependent on the integrated foundation; require identity authorization and customer/employee lifecycle tests.
5. Integrate PR #15 only after catalog/inventory/order contracts and identity/session contracts are stable.
6. Only then connect Builds 007–010.17 to the accepted identity, catalog, order and permission interfaces.

No PR was merged and no production migration or live payment was activated during this pass.


## Latest foundation-to-checkout pass — 2026-11-06

### PR #15 CI is now fully green

Workflow run [#680](https://github.com/lynchcous-wq/mme-os/actions/runs/42173200346) on checkout branch commit `8928281c83805b84e49a0809ea466abab9ecaf6f` completed successfully:

- Supabase local startup: passed.
- Complete migration chain on a fresh local database: passed.
- Full pgTAP database suite: passed.
- TypeScript check: passed.
- Next.js production build: passed.
- Supabase Edge Function type-check: passed.

PR #15 remains an open draft targeting `integration/build001-catalog-inventory`. Its Vercel preview checks still report the account build-rate-limit/upgrade failure. GitHub Actions green is not a deployed preview or production release.

### Build 004 identity integration findings

Inspected the Build 004 helper, authorization RPC and protected inventory inspection routes on `integration/build004-identity-validation`.

- `authenticateAndAuthorizeEmployee` verifies the bearer token against Supabase Auth, derives the actor UUID from the Auth response, calls server-only `mme_authorize_employee_action`, and fails closed on an unavailable authorization service.
- The identity model intentionally separates `auth.users.id` from `mme_person_identities.id`. The four inventory inspection routes resolve the person identity separately and derive product/location authorization scope from protected database rows.
- Legacy authorization and transactional RPC controls are retained as defense in depth.
- Build 004 documentation reports the four route contract suites and live local Supabase Auth/RPC smoke test as passing on its validated commits. The live smoke test is not full request-level coverage of all four endpoints and does not prove production cutover.
- Permission migration and production authorization cutover remain explicitly blocked.

### Checkout pricing service is a concrete P0 dependency

PR #15's checkout Edge Function is intentionally dependent on `MME_CHECKOUT_PRICING_URL` and `MME_CHECKOUT_PRICING_SECRET`. No trusted pricing-service endpoint was found in the inspected PR #13/#14/#15 file changes. The checkout cannot prepare a payable order until that service exists and is configured.

The required trusted service contract is now explicit:

1. Accept calls only from the checkout Edge Function using a constant-time verified server secret; never trust browser-supplied customer identity or price.
2. Verify the supplied Auth user UUID corresponds to exactly one `mme_person_identities.auth_user_id` record and an eligible active customer relationship.
3. Validate every product, store location, publication state, quantity and serialized-unit selection against live database records.
4. Recompute item eligibility and return only canonical `product_id`, `location_id`, quantity and optional serialized-unit IDs; the mixed-order RPC independently snapshots current DB prices and reserves stock atomically.
5. Validate pickup selection against active MME locations; validate shipping address and supported destination.
6. Calculate tax from an approved tax service/ruleset and shipping charges from an approved carrier/rate policy. Do not guess tax rates, shipping charges, or discounts.
7. Apply only persisted, approved discount/subscription/rewards entitlements; browser-submitted discounts are never authoritative.
8. Return the exact schema expected by `create-checkout-payment`: customer identity ID, canonical items, tax cents, fulfillment cents, discount cents and immutable fulfillment snapshot.
9. Enforce strict request/response schemas, bounded payloads, timeouts, rate limits, structured non-sensitive logs and idempotent quote semantics.
10. Add tests for inactive/frozen customer, invalid product/location, stale stock, wrong serialized unit, invalid pickup, unsupported shipping destination, tax/shipping service outage, discount abuse, duplicate requests and malformed provider response.

**No tax provider, shipping-rate provider, or approved tax/discount policy has been selected/verified in this audit.** Keep the endpoint fail-closed until these business and provider inputs are supplied. Do not substitute zero tax or arbitrary flat shipping rates.

### Next implementation work order

1. Build and test the trusted checkout pricing endpoint against the exact Edge Function contract, with tax and fulfillment adapters required by configuration.
2. Add request-level integration tests for Build 004's four protected inventory-inspection routes using local Supabase and test identities/permissions.
3. Reconcile PR #11 atomic order/reservation migration with PR #13 catalog/inventory migrations and PR #14 identity dependencies.
4. Re-run complete CI on the final combined integration head, then perform Stripe test-mode end-to-end tests.
5. Keep all PRs in draft and do not merge or deploy until required checks, business policy and owner approvals are complete.
