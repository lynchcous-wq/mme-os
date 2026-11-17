# Build 011.23 — Production Readiness & Release Gate

## Objective
Establish a repeatable, fail-closed release gate for MME OS Build 011.22 and later. This build is additive documentation only; it does not merge branches, alter production data, change credentials, or deploy.

## Source of truth
- Repository: `lynchcous-wq/mme-os`
- Release candidate: `build-01122-customer-auth-foundation`
- Target: `main`
- At the time of this record, GitHub comparison reported the candidate 13 commits ahead and 0 behind.
- Existing review artifact: pull request #200 (the repository rejected creation of a duplicate PR for this head branch).

## Release blockers carried forward
1. Confirm isolated test Supabase project and preview-only credentials; production service-role credentials must not be used by untrusted preview deployments.
2. Implement rate limiting and abuse protection for customer sign-up, sign-in, and confirmation callback paths. Apply provider-side controls as well as application controls where available.
3. Implement customer activation as a narrowly scoped, server-authorized operation. Browser input must not set customer relationship status, approver identity, or approval timestamps.
4. Complete CEO bootstrap only through verified mailbox ownership, MFA, recent authentication, reviewed role assignment, explicit approved permission grants, and append-only audit. No bootstrap from email address or user metadata alone.
5. Add automated tests for successful and denied flows, including anonymous, customer-only, employee-only, pending/revoked role, missing permission, stale session, missing MFA, self-approval, duplicate decision, invalid transition, and cross-customer access.
6. Verify employee sign-in and customer sign-in independently. Employee/customer relationships must remain independent.
7. Verify all linked storefront routes before release, including at minimum: `/`, `/products`, `/cart`, `/account`, `/employee-sign-in`, and the financing inquiry/application route. A route returning HTTP 200 is not sufficient if it renders an error, placeholder, or wrong destination.
8. Verify sign-up, email confirmation, sign-in, session refresh, sign-out, and pending-customer denial in an isolated preview environment.
9. Verify production environment variables are server-only, least-privilege, and scoped to the correct Vercel project/environment. Never expose the Supabase service-role key in a `NEXT_PUBLIC_*` variable or browser bundle.
10. Obtain explicit release approval before merging or promoting to production.

## Required CI checks
Run from the repository root in a clean checkout of the exact candidate commit:
- `npm ci`
- `npm run lint` (currently maps to `tsc --noEmit`)
- `npm run build`
- Automated unit/integration/security tests once configured.

Record the commit SHA, Node.js version, command exit status, and test artifact links. Do not infer a passing build from a prior deployment or a route's HTTP status.

## Preview smoke-test matrix
| Area | Required assertion |
|---|---|
| Homepage | Loads without runtime errors; primary navigation is valid |
| Catalog | Product listing renders real catalog state or an intentional empty state |
| Cart | Route exists; empty and populated states behave correctly |
| Customer account | Registration and sign-in use server endpoints; no role input accepted |
| Email confirmation | Callback verifies provider result and binds session to the same user |
| Customer access | Pending/suspended/frozen customer is denied portal access |
| Employee sign-in | Existing employee flow remains functional and isolated |
| Financing | Inquiry/application route exists, validates inputs, and does not imply approval |
| Security | No service key in client bundle; cookies are HttpOnly, Secure in production, SameSite=Lax |
| Errors | No uncaught runtime errors, broken internal links, or misleading success states |

## Deployment sequence
1. Review PR #200 and reconcile its base/head with the current candidate.
2. Complete every blocker above in preview.
3. Require green CI and security review.
4. Obtain explicit approval.
5. Merge using the repository's approved merge strategy.
6. Confirm Vercel builds the intended production project from `main`.
7. Promote only the verified deployment; do not use a stale preview URL as production.
8. Run production smoke tests and verify the production domain points to the intended deployment.
9. Record deployment ID, commit SHA, timestamp, smoke-test outcomes, and rollback target.

## Rollback criteria
Rollback immediately if authentication, employee access, customer isolation, RLS, payment integrity, or critical storefront navigation regresses. Preserve logs and audit events. Do not attempt a compensating production database change without a reviewed migration and approval.

## Current status
- [x] Candidate branch identified.
- [x] Candidate-to-main comparison performed.
- [x] Existing PR detected; duplicate PR creation rejected by GitHub.
- [x] Release blockers and test matrix documented.
- [ ] Automated CI results verified for the candidate.
- [ ] Preview security and end-to-end tests passed.
- [ ] Missing storefront routes resolved and verified.
- [ ] PR review approved.
- [ ] Explicit production release approval received.
- [ ] Production deployment and smoke tests completed.

**Release decision: HOLD.** This build does not authorize merge, production database mutation, or deployment.
