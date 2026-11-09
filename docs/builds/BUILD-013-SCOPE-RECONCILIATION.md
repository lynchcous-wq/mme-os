# Build 013 — Scope Reconciliation and Implementation Gate

**Record type:** Pre-implementation governance record  
**Build number:** 013 (reserved; functional title and scope are not yet approved)  
**Prepared:** 2026-11-08  
**Repository:** `lynchcous-wq/mme-os`  
**Base:** `main` at `80caffff8cb7de67c224dded84df422dbc5b0b76`  
**Change policy:** Additive-only; preserve existing build identifiers, branches, migrations, and source history.

## 1. Purpose

This record starts the Build 013 workstream without inventing a functional build title or silently assigning capabilities. It captures the repository evidence required to establish the approved scope and implementation sequence.

This record is not a claim that Build 013 application functionality has been implemented.

## 2. Verified repository facts

- The default branch is `main`; the inspected head is `80caffff8cb7de67c224dded84df422dbc5b0b76`.
- The latest commit message identifies work as **Build 011: integrate purchasing and employee sign-in**.
- The latest commit includes employee sign-in/session endpoints and Build 011 identity/security migrations and documentation.
- The repository contains architecture documents `docs/BUILD-001-ARCHITECTURE.md` through `docs/BUILD-009-ENTERPRISE-POS.md`; their titles and scope do not align one-to-one with the separately recovered master roadmap.
- The repository contains `docs/builds/BUILD-011-PURCHASING-RECEIVING-INTEGRATION.md`, which labels Build 011 as Purchasing & Receiving Integration and explicitly describes itself as an integration contract/implementation gate.
- The inspected `main` tree does not contain a canonical Build 012 specification or a Build 013 functional specification.
- `README.md` still describes the public application as a storefront shell and says the live catalog, account system, checkout, Stripe connection, and inventory integration are not established by that README.
- Existing repository documentation repeatedly distinguishes specifications, branch-only work, code-reviewed work, tested work, migrated work, integrated work, and production-verified work. Those states must remain separate.

## 3. Numbering conflict — do not resolve by assumption

The previously recovered master roadmap assigns:
- 001 Foundation
- 002 CRM + Employees
- 003 Products + Inventory
- 004 Deal Desk
- 005 Financing
- 006 F&I + Contracts
- 007 Funding
- 008 Commissions + Payroll
- 009 Accounting
- 010 Customer Portal
- 011 Management + AI
- 012 Integrations + Production

The repository's current detailed architecture documents and implementation branches use different titles and workstream identifiers. In particular, the repository's Build 011 purchasing/receiving stream conflicts with the master roadmap's Build 011 Management + AI.

**Rule:** preserve all existing labels and histories. Do not rename, merge, renumber, or promote a branch solely to make the sequences appear consistent. A project-owner-approved crosswalk is required.

## 4. Build 013 entry criteria

Before functional implementation begins, record and approve:

1. The canonical Build 013 title and business outcome.
2. Whether Build 013 follows the recovered master roadmap or an explicitly approved implementation-stream crosswalk.
3. Included modules, exclusions, dependencies, and ownership boundaries.
4. Existing branches, files, migrations, routes, workers, and tests that already satisfy any part of the approved scope.
5. The authoritative system of record for each data domain.
6. Role permissions, CEO approval gates, audit requirements, privacy boundaries, and security controls.
7. Acceptance tests, migration strategy, rollback/forward-recovery plan, and deployment gates.

## 5. Implementation safeguards

- Additive-only changes; no destructive cleanup or broad branch merges.
- Inspect the current file and schema before every change.
- Never create duplicate tables, routes, workers, policies, migrations, or build identifiers.
- Keep secrets and customer/employee sensitive data out of Git.
- Do not apply migrations or change production configuration as part of a documentation-only scope reconciliation.
- Do not claim a feature is live based on a branch, specification, commit, or successful type check alone.
- Require tests and environment-specific verification before marking any capability complete or production-ready.

## 6. Current status

| Work item | Status |
|---|---|
| Repository and default-branch inspection | Complete for this kickoff pass |
| Build-number conflict identified | Confirmed; unresolved |
| Existing Build 011 purchasing/receiving record located | Confirmed |
| Canonical Build 012 document in repository | Not found in inspected default-branch tree |
| Canonical Build 013 title/scope | Not established |
| Build 013 functional code | Not started; scope gate required |
| Production deployment or migration | Not performed |

## 7. Next action

Obtain owner approval of the Build 013 title and scope, then perform a file-level crosswalk against existing code and branches. Implement only the first approved, non-duplicative functional slice on a dedicated branch with tests and recorded evidence.


## 8. Implementation-stream branch inventory — follow-up pass

A second branch-search pass was performed on the repository. The results below are **branch-name evidence only**; they do not prove that every branch contains complete code, passes tests, is merged, or is deployed.

### 010 inventory stream

The search returned the following existing branches:

- `build/010.75-inventory-reconciliation`
- `build/010.76-inventory-ledger-api`
- `build/010.77-inventory-ledger-database`
- `build/010.78-pos-warehouse-inventory-bridge`
- `build/010.79-inventory-reconciliation-exceptions`
- `build/010.80-purchase-orders-receiving-vendor-intake`
- `build/010.81-vendor-management-performance`
- `build/010.82-multi-location-inventory-transfers`
- `build/010.83-availability-reservations-website-stock-sync`
- `build/010.84-cycle-counts-physical-audits-stock-adjustments`
- `build/010.85-inventory-valuation-cogs-profitability`
- `build/010.86-inventory-forecasting-replenishment`
- `build/010.87-inventory-lifecycle-aging-disposition`
- `build/010.88-inventory-intelligence-executive-kpis`
- `build/010.89-inventory-automation-event-orchestration`

The earlier governance register separately records 010.00–010.24 security/notification branches, including duplicate identifiers 010.03 and 010.19. That historical inventory must be revalidated branch-by-branch before being treated as a complete current list.

### 011 implementation stream

The branch search returned:

- `implementation/build-011-08-commerce-identity-cart-checkout`
- `implementation/build-011-09-identity-access-foundation`
- `implementation/build-011-10-authentication-consolidation`
- `implementation/build-011-11-identity-migration-reconciliation`
- `implementation/build-011-12-supabase-schema-preflight`
- `implementation/build-011-13-readonly-schema-snapshot`
- `implementation/build-011-14-migration-safety-checks`
- `implementation/build-011-15-identity-rls`
- `implementation/build-011-16-ceo-role-foundation`
- `implementation/build-011-17-ceo-provisioning-guard`
- `implementation/build-011-18-ceo-permission-matrix`
- `implementation/build-011-19-server-authorization`
- `implementation/build-011-20-account-freeze`
- `implementation/build-011-20-employee-sign-in-route`
- `implementation/build-011-purchasing-receiving-integration`

Two distinct branches use 011.20. Preserve both identifiers until their relationship is established by file/commit comparison. Do not infer that all these branches are integrated into `main`.

### Foundation and integration branches

The search also returned:

- `implementation-foundation-001-009`
- `foundation/build001-mixed-cart-checkout`
- `implementation/build001-authenticated-checkout-ui`
- `integration/build001-catalog-inventory`
- `work/build008-build001-catalog-routes`
- `build004/identity-matrix-preview`
- `integration/build004-identity-validation`

These branch names show overlapping work across foundation, catalog/inventory, checkout and identity. They require ancestry, migration and changed-file comparison before any merge or consolidation.

## 9. Reconciliation result and next safe action

The branch inventory confirms that the repository's implementation streams have extensive existing work that is not represented cleanly by the recovered master roadmap. It is therefore unsafe to begin unrelated Build 013 application features now.

The next implementation action is a **read-only crosswalk**: compare branch ancestry and changed files for the foundation, catalog/inventory, checkout, identity, purchasing/receiving and 010 inventory/security streams; map migrations, routes, RPCs, workers and tests; record duplicate/overlap candidates and dependency order. No branch merges, renames, database writes or production changes are authorized by this document.

### Updated status

| Work item | Status |
|---|---|
| Build 013 governance branch and kickoff record | Committed |
| 010.75–010.89 branch names inventoried | Search results recorded; code not yet reviewed |
| 011.08–011.20 branch names inventoried | Search results recorded; code not yet reviewed |
| Foundation/catalog/checkout/identity branch overlap identified | Confirmed by branch names; ancestry not yet compared |
| Canonical build-number crosswalk | Still unresolved |
| Build 013 functional title and scope | Awaiting owner approval |
| Build 013 application implementation | Not started; do not invent scope |


## 10. Branch ancestry and pull-request crosswalk — follow-up

Compared selected implementation branches against `main` using GitHub's commit comparison. The inspected default branch was current at the time of this pass; results are relative to the repository's then-current `main`.

| Branch | Relationship to main | Files returned | Interpretation |
|---|---:|---:|---|
| `implementation-foundation-001-009` | 0 ahead / 33 behind | 0 | No unique branch commits to integrate; branch is behind main |
| `integration/build001-catalog-inventory` | 473 ahead / 33 behind | 298 (comparison response) | Large divergence; not safe for a blind merge |
| `integration/build004-identity-validation` | 616 ahead / 33 behind | 300 (response cap) | Large divergence; not safe for a blind merge |
| `implementation/build001-authenticated-checkout-ui` | 532 ahead / 33 behind | 300 (response cap) | Large divergence; not safe for a blind merge |
| `implementation/build-011-20-employee-sign-in-route` | 40 ahead / 1 behind | 34 | Narrower change set, but still requires dependency and CI review |
| `build/010.89-inventory-automation-event-orchestration` | 15 ahead / 1 behind | 15 | Compact implementation stream; compare and validate before integration |

A compare response capped at 300 files is incomplete for detailed review. The 001/004 integration branches must be split into reviewed dependency slices; do not treat the reported ahead count as a proposed merge size.

### Pull-request state sampled

The following PR metadata was fetched directly:

| PR | Scope | State | Draft | Mergeable at inspection | Changed files |
|---|---|---|---|---|---:|
| #13 | Build 001 catalog/inventory integration | Open | Yes | No | 298 |
| #14 | Build 004 identity validation | Open | Yes | Yes | 44 |
| #15 | Authenticated checkout + Stripe UI | Open | Yes | Yes | 25 |
| #186 | Build 010.89 customer cart foundation | Open | Yes | Yes | 3 |
| #187 | Build 010.90 order payment finalization | Open | Yes | Yes | 3 |
| #196 | Build 010.99 refund request portal/order tracking | Open | Yes | Yes | 4 |

The repository's current open-PR search also returned the consecutive customer commerce PRs **#176–#196**, covering Build 010.79–010.99 (with a gap at 010.?? where the search result omitted PR #??). This is an open review queue, not a merged release. PR #186/#187/#196 remain drafts and are not production evidence. The exact dependencies and head/base relationships for each PR still require individual inspection.

### Immediate integration conclusion

1. **Do not merge** the large Build 001/004 integration branches as a whole. Their 473/616-commit divergence and response-capped file lists require decomposition and ancestry review.
2. Keep PRs #13–#15 in draft until the integration dependency chain, migration ordering, CI and pricing/tax/shipping dependencies are resolved.
3. The employee sign-in branch is much narrower than the large foundation branches, but it still has 40 commits ahead and one behind; verify its current PR/merge status and CI before integrating.
4. The 010.89 branch contains 15 documentation changes for the inventory stream and is only one commit behind main. Its PR/review state must be checked before treating it as accepted.
5. Keep the 010.90–010.99 commerce PR series separate from the canonical master roadmap until the owner-approved numbering crosswalk exists.

## 11. Updated evidence ledger

| Work item | Status |
|---|---|
| Selected branch ancestry comparisons | Complete for six branches listed above |
| Large integration divergence identified | Confirmed |
| Selected PR draft/mergeability metadata | Inspected for six PRs |
| Full file-level crosswalk of 001/004 integration branches | Not complete; compare output capped |
| Individual migrations/routes/RPC dependency graph | Not complete |
| All 010.90–010.99 PR dependencies and CI | Not complete |
| Canonical numbering crosswalk | Unresolved |
| Build 013 functional scope/title | Not approved |
| Build 013 application implementation | Not started |


## 12. Checkout integration CI failure isolated and test contract corrected

A focused review of PR #15 (Build 001 authenticated checkout + Stripe payment UI) found:
- TypeScript/lint and production build job: passed.
- Supabase Edge Function type-check job: passed.
- Supabase migration + pgTAP job: failed 1 of 892 assertions.
- The failing assertion was test 9 in `supabase/tests/build001_mixed_cart_order_creation.test.sql`: **"trusted server role can create mixed orders"**.

Root cause from the inspected migration/test contract:
- Migration `20261103006600_build001_atomic_pricing_quote_reservation.sql` adds a new 10-argument quote-bound RPC overload.
- It intentionally revokes `service_role` execution from the legacy 9-argument overload so a trusted caller cannot bypass quote validation.
- The existing pgTAP assertion still expected `service_role` to execute that legacy overload. The assertion therefore contradicted the new security design.

Corrective change committed to PR #15 branch:
- Updated the pgTAP test to assert the legacy overload is present but not executable by `service_role` or `authenticated`.
- Added an explicit assertion that `service_role` can execute the new 10-argument quote-bound overload.
- Retargeted the function-definition checks to the new overload.
- Preserved the inventory locking, serialized-unit, idempotency, and order-line assertions.

Commit: `e1c57c7b37e0869342f224b83a26e624fb63d87a`  
Branch: `implementation/build001-authenticated-checkout-ui`  
File: `supabase/tests/build001_mixed_cart_order_creation.test.sql`

**Validation status:** correction is committed; a workflow run for the new head commit was not yet returned by the workflow-run lookup at inspection time. The earlier failing run is not considered repaired until CI reruns and passes. No merge, database migration to a hosted environment, or deployment was performed.

### Updated work ledger

| Work item | Status |
|---|---|
| PR #15 failure localized | Complete |
| Contradictory pgTAP privilege expectation corrected | Committed to PR branch |
| New-head CI rerun | Pending visibility/verification |
| PR #15 merge | Not performed |
| Production checkout/Stripe operation | Not verified |


## 13. PR #15 corrective-commit CI verification — in progress

The corrected test commit `e1c57c7b37e0869342f224b83a26e624fb63d87a` triggered GitHub Actions run **42512882427** (`MME OS CI`).

At the latest inspection:
- **TypeScript and production build:** passed.
- **Supabase Edge Function type-check:** passed.
- **Supabase migration and pgTAP tests:** still in progress; the local Supabase startup step had not completed. The migration chain and pgTAP assertions had not yet run, so the prior test failure is not yet confirmed fixed.

PR #15 remains open and draft. GitHub reports it mergeable, but mergeability is not an approval or a passing test suite.

Vercel deployment status checks for the PR head continue to fail with the previously observed Vercel build-rate-limit upgrade URL. These checks are separate from GitHub Actions and do not establish that the code has been deployed.

### Current gate

| Gate | Status |
|---|---|
| Application type-check/build | Passed |
| Edge Function type-check | Passed |
| Fresh local migration-chain replay | Pending CI |
| pgTAP regression suite | Pending CI |
| Vercel preview deployment | Blocked by Vercel build-rate limit |
| PR approval/merge | Not performed |
| Production deployment | Not performed |


## 14. PR #15 database verification passed; next integration gate selected

GitHub Actions run **42512882427** for corrective commit `e1c57c7b37e0869342f224b83a26e624fb63d87a` completed successfully.

All three CI jobs passed:
- TypeScript and production build.
- Supabase Edge Function type-check.
- Supabase migration replay against a fresh local database and the complete pgTAP database test suite.

This confirms the earlier pgTAP privilege-contract failure is corrected in the isolated CI environment. It does **not** prove hosted Supabase has been migrated, Stripe live payments are configured, or production checkout is deployed.

PR state at this inspection:
- **PR #15** remains open and draft; GitHub reports mergeable; all three CI jobs pass.
- **PR #14** (Build 004 identity foundation integration validation) remains open and draft; GitHub reports mergeable; its inspected CI run **41964831695** passed all three jobs.
- **PR #13** (Build 001 catalog/inventory integration) remains open and draft; GitHub reports not mergeable; no PR-triggered workflow run was returned for its current head.

### Recommended next gate

Review PR #14's exact migration and identity-policy diff against the existing main-branch identity/security work. Verify no duplicate identity tables, conflicting RLS policies, duplicate migrations, or conflicting role/permission sources before considering it for merge. Keep PR #13 blocked until its merge conflict is resolved and its change set is decomposed; do not merge either PR simply because a CI run passed.

### Updated status

| Gate | Status |
|---|---|
| PR #15 application checks | Passed |
| PR #15 Edge Function checks | Passed |
| PR #15 fresh migration replay | Passed |
| PR #15 pgTAP suite | Passed |
| PR #15 approval/merge | Pending; still draft |
| PR #14 CI | Passed; still draft |
| PR #14 identity diff review | Next |
| PR #13 mergeability/CI | Blocked |
| Hosted Supabase / Stripe live checkout | Not verified |
| Production deployment | Not performed |


## 15. PR #14 identity/security diff review — integration blocked pending authorization alignment

Reviewed all 44 changed paths in PR #14, including its four API routes, server authorization helper, identity foundation migrations, CEO/global-freeze parity migration, diagnostics, and pgTAP/runtime tests.

### Confirmed design strengths

- Auth user IDs are explicitly mapped to separate `mme_person_identities.id` values; inspection records no longer assume these UUIDs are interchangeable.
- The helper validates the bearer token through Supabase Auth and obtains the actor ID from the verified response rather than request JSON.
- The identity tables are RLS-enabled and direct client privileges are initially revoked.
- The migrations add append-only identity audit behavior, whole-login lock state, and a centralized server-side permission decision.
- CEO bypass is limited to existing resource families and depends on explicit CEO provisioning plus active employee/identity state; the global employee freeze denies access.
- CI for PR #14's inspected head passed application build/type-check, Edge Function type-check, fresh migration replay, and pgTAP tests.

### Integration blocker: two authorization engines

The PR introduces and wires route checks through `public.mme_authorize_employee_action(...)` using a server-role RPC. The current `main` branch also contains Build 011.19's `public.mme_authorize(...)` evaluator and `private.mme_session_is_active()` helper.

These are not equivalent contracts:
- Build 004's helper validates the bearer with Auth and checks person/employee status, role assignment, grants, scopes, CEO parity and global employee freeze.
- Build 011.19's evaluator additionally requires an active Auth session row, validates recent-auth `iat`, and enforces MFA/AAL requirements for approved permission templates.
- PR #14's route helper does not call `mme_authorize` or `private.mme_session_is_active()`; therefore, a route protected only by the PR helper does not inherit Build 011.19's session/MFA/recent-auth gates.

This creates a potential authorization-policy split. It is not proof of an exploitable bypass in the currently deployed application, but it is a material integration blocker: the same employee action could be accepted by one engine and denied by the other.

### Additional review notes

- PR #14 retains the legacy `mme_employee_authorize_inventory_action` checks after adding the Build 004 authorization check. This may be intentional defense in depth, but the two evaluators' scope semantics and failure behavior must be covered by a parity matrix.
- The PR adds identity tables through its own foundation migrations. The current `main` migrations reference these tables but do not independently create the full identity schema. Fresh-chain CI passed on the PR head; hosted migration history and the live schema still need reconciliation before any hosted apply.
- CEO permission templates in the current `main` migration are seeded as `pending_review`. They are metadata, not runtime grants; PR #14's CEO legacy bypass must not be confused with automatic grants for new resource families.
- The PR remains draft; passing CI does not approve the authorization design.

### Required remediation before merge

1. Select one canonical server-side authorization entry point, or define an explicit, tested adapter that enforces the union of required controls without allowing a weaker path.
2. Ensure protected employee routes enforce the intended active-session, MFA/AAL, recent-auth, whole-login lock, employee status, global freeze, role/grant and scope rules.
3. Build a table-driven parity suite across Build 004 and Build 011 decisions, including CEO, global freeze, locked identity, terminated employee, missing role, expired assignment, scope mismatch, MFA absent, stale `iat`, and revoked/expired session.
4. Keep the legacy inventory permission check only if the parity suite proves it is required and cannot produce contradictory authorization outcomes.
5. Re-run full CI on the revised PR head and keep it draft until the policy owner approves the unified model.

### Current decision

**Do not merge PR #14 yet.** Its CI is green, but the authorization engines have not been unified and session/MFA parity is not proven. No production migration or deployment was performed.


## 16. Authorization parity gate — contract tests added to PR #14

Added a dedicated route-level contract suite to the PR #14 identity integration branch:
- `tests/build004-authorization-parity.contract.test.mjs`
- Package script: `npm run test:build004-authorization-parity`
- GitHub Actions CI now runs this suite on the Build 004 identity branch.

The suite checks that:
- The shared helper validates bearer sessions through Supabase Auth.
- Actor identity comes from the verified Auth response.
- The Build 004 authorization RPC is called with service-role credentials and fails closed.
- All four employee inspection routes use the shared authorization helper.
- The legacy inventory authorization calls remain explicit and are not mistaken for the centralized identity gate.

Commits on `integration/build004-identity-validation`:
- Test suite: `f55baf7836f638b5f448c9d7d8298697405f8b20`
- Package script: `4e2ae54df8c95d3da38210d01541a29132803ca8`
- CI registration: `78dc930a1c2c5fc6aa08531677e0966bb8c3137e`

**Important limitation:** These are contract tests for the current Build 004 route wiring. They do not make the Build 004 RPC enforce Build 011's active-session, AAL/MFA, recent-auth, or permission-template gates. The two engines remain an unresolved policy integration issue. No production code was changed to claim parity, no hosted database migration was applied, and PR #14 remains draft.

### Updated gate

| Item | Status |
|---|---|
| Build 004 route/helper contract suite | Added |
| Package test command | Added |
| CI workflow registration | Added |
| New-head CI run | Not yet visible |
| Build 011 session/MFA/recent-auth parity | Not implemented |
| Authorization policy owner approval | Pending |
| PR #14 merge | Blocked |


## 17. Authorization parity CI failure diagnosed and test corrected

The new PR #14 CI run **42513580780** executed the added authorization parity suite. Seven assertions passed and one assertion failed because the test incorrectly expected the root inspection submit route to call the legacy inventory authorization RPC. Source inspection confirmed:
- The root submit route uses the shared Build 004 identity helper and does not call the legacy inventory RPC.
- The history and photos routes retain the legacy inventory permission check after the shared identity gate.
- The resolve route uses the shared identity helper and does not call the legacy inventory RPC.

Corrected the contract test to assert the actual route-specific behavior instead of treating the four routes as identical.

Commit: `4d64110878a8853ed6b1bb9a66aafc38535f3189`  
File: `tests/build004-authorization-parity.contract.test.mjs`  
Branch: `integration/build004-identity-validation`

New-head CI run **42513719963** was created and was pending at the time of this record update. No pass is claimed until that run completes.

### Current gate

| Item | Status |
|---|---|
| Initial parity contract suite | 7 passed / 1 failed |
| Route-specific test expectation corrected | Committed |
| New-head CI | Pending |
| Build 004 / Build 011 authorization unification | Not implemented |
| PR #14 merge | Blocked |
| Hosted migration or production deployment | Not performed |


## 18. Authorization parity test follow-up — second route expectation corrected

The new-head CI run **42513719963** completed with:
- Supabase migration replay, pgTAP and live Auth/Build 004 authorization integration test: passed.
- Supabase Edge Function type-check: passed.
- TypeScript/production-build job: failed in the authorization parity contract suite.

The failing assertion was another route expectation: the resolve route retains the legacy `mme_employee_authorize_inventory_action` RPC, while the root inspection submit route does not. The test had incorrectly excluded both routes.

Corrected the suite to expect the legacy permission RPC on history, photos and resolve routes, and not on the root submit route.

Commit: `cc8519fd83e8916e1441c0a9e42a71a3c73ba971`  
New CI run: **42568541298** (queued at time of this record update).

No production code or authorization policy was weakened. This remains a test-only correction. Build 004/Build 011 authorization-engine unification is still outstanding; PR #14 remains draft and blocked from merge pending policy reconciliation and passing CI.
