# MME OS — Cloudflare Hosting Migration & Deployment Budget Policy

**Status:** Migration plan committed on an isolated branch. No Cloudflare account has been connected, no runtime adapter has been installed, no DNS has been changed, and no deployment has been performed.

## 1. Hosting decision

- **Source of truth:** GitHub repository `lynchcous-wq/mme-os`.
- **Application hosting target:** Cloudflare Workers for the full-stack MME OS application.
- **Static asset delivery:** Cloudflare static assets/CDN as supported by the selected Workers deployment.
- **Database and identity:** Keep the existing Supabase project as the database/auth authority unless a separately approved migration is made.
- **Payments:** Keep Stripe as the payment provider; hosting migration must not alter payment ownership, webhook verification, or secret handling.
- **Domain:** Preserve `muchmoreelectronics.com` and its existing DNS until Cloudflare staging and production checks pass.
- **Vercel:** Do not create new Vercel deployments. Keep the existing production target available only as a rollback path until Cloudflare is verified, then retire it deliberately.

Cloudflare identifies Workers as its primary application platform and recommends Workers for full-stack applications. Pages is appropriate for static sites; it is not the preferred target for this full-stack Next.js application. Cloudflare's current Next.js guide recommends vinext as its default path, while its OpenNext guide positions OpenNext as the maintenance path for existing OpenNext applications.

## 2. Repository audit snapshot

At the inspected commit:
- `package.json` identifies Next.js `^15.2.4`, React 19, TypeScript, and scripts `build`, `lint`, `dev`, and `start`.
- `next.config.ts` only disables the `X-Powered-By` header.
- No `wrangler.toml`, `wrangler.jsonc`, `vercel.json`, or inspected GitHub CI workflow was present at the repository root/expected path.
- The README describes the current baseline as a storefront shell with illustrative product cards and placeholder product/account routes; it explicitly says no live catalog, account system, checkout, Stripe connection, or inventory integration is established by that snapshot.
- The prior POS and inventory build documents are specifications and do not prove the described runtime services are present.

This audit snapshot is not a complete runtime or Cloudflare compatibility audit. Reinspect the current default branch, all active application routes, dependencies, environment variables, Supabase usage, Stripe webhooks, image handling, and deployed behavior before making production changes.

## 3. Next.js compatibility strategy

The inspected repository uses Next.js `^15.2.4`. Do not force a framework major-version upgrade as part of the hosting cutover.

- First run Cloudflare's current compatibility check for vinext on the exact application. Cloudflare currently recommends vinext as the default Next.js-on-Workers path; its initializer is described as non-destructive and keeps the existing Next.js development setup available while testing.
- Do not assume compatibility merely because the initializer succeeds. Run the compatibility check, build, route-level tests, and local `workerd` preview. Compare server rendering, route handlers, authentication, caching, images, middleware, and all used Next.js APIs.
- If vinext does not safely support the app's actual Next.js 15 feature set, evaluate `@opennextjs/cloudflare` as the conservative compatibility route. Cloudflare documents OpenNext for maintaining existing OpenNext applications and supports most Next.js features, but Node.js middleware introduced in Next.js 15.2 is not supported by its current feature matrix.
- Choose one adapter only after the compatibility matrix is documented and all required routes pass. Do not simultaneously introduce a framework upgrade and a hosting cutover unless separately approved.
- Do not use static export as a shortcut if authenticated routes, server actions, route handlers, dynamic rendering, or server-side integrations are required.

## 4. Deployment policy — deploy only when needed

**Hard requirement:** Total Cloudflare production and preview deployments must remain below 500 in every calendar month.

Set an internal operating ceiling of **400 total deployments per calendar month**. The remaining 100 are reserved as a safety buffer. At 350, require release-owner review; at 375, require executive approval; at 400, block further deployments until the next month or a documented emergency exception is approved. Never intentionally approach 500.

Count every deployment attempt that creates or promotes a Cloudflare version/deployment, including preview deployments. Builds and tests that do not upload or deploy to Cloudflare do not count as Cloudflare deployments.

### Trigger rules

- GitHub pushes, commits, merges, documentation updates, and ordinary build-spec changes must not automatically deploy to production.
- GitHub Actions may run lint, typecheck, unit tests, integration tests, security checks, and a local/workerd build without deploying.
- Cloudflare production deployment must be manually initiated through a protected GitHub Actions `workflow_dispatch` release workflow.
- Require a protected GitHub Environment approval before production deployment.
- No scheduled production deploys.
- No automatic deployment for every feature branch or pull request.
- Use preview deployments only when a reviewer cannot adequately verify the change locally or through non-deploy checks.
- Group additive changes into release batches; do not deploy each individual build document.
- Documentation-only changes never trigger Cloudflare deployment.
- Rollbacks are treated as deployments for budget accounting and require an incident/release reason.

### Budget ledger and enforcement

Before enabling production deployment:
1. Establish one auditable deployment ledger recording month, environment, commit SHA, initiator, reason, Cloudflare deployment/version ID, result, and whether it counts against the budget.
2. Read the current month's Cloudflare deployment/version history before authorizing a new deployment.
3. Enforce the 400 internal ceiling in the release workflow using a durable, concurrency-safe counter; do not rely only on a human-maintained note.
4. Make the workflow fail closed if the ledger or current usage cannot be read.
5. Prevent concurrent production release workflows from racing past the ceiling.
6. Alert the release owner at 350 and require executive approval at 375.
7. Block at 400 unless an approved emergency exception is recorded; the hard external constraint remains fewer than 500.
8. Reconcile the ledger against Cloudflare's authoritative deployment history monthly.

Do not claim a hard technical cap until the counter is implemented, tested against concurrent workflow runs, and reconciled to Cloudflare history.

## 5. GitHub and Cloudflare workflow

GitHub remains the only source-control and review authority.

Recommended flow:
1. Developer commits to a feature branch.
2. GitHub Actions runs CI only: install, lint/typecheck, tests, build, dependency/security checks.
3. Pull request review and required checks complete.
4. Release candidate is tested locally or in a non-deploying `workerd` preview.
5. If an actual hosted preview is essential, create one manually and record it in the deployment ledger.
6. A release owner manually starts the protected production workflow against an approved commit SHA.
7. The workflow checks the budget, tests the exact commit, deploys through Wrangler, and records the Cloudflare result.
8. Post-deploy smoke tests verify homepage, customer/employee entry points, catalog routes, API health, Supabase connectivity, Stripe webhook behavior (without live charges), security headers, and error rates.
9. If critical checks fail, execute the approved rollback and record it against the deployment budget.

Do not enable Cloudflare Workers Builds or Git push auto-deploy until the deployment-count policy can reliably prevent unnecessary deployments. GitHub Actions with manual dispatch is the preferred initial control plane.

## 6. Cloudflare account and secret setup

Required account actions must be completed by an authorized account owner:
- Create/select the Cloudflare account and confirm plan and account ID.
- Connect the GitHub repository only after reviewing repository access scope.
- Create a narrowly scoped Cloudflare API token for the intended Worker and deployment operations.
- Store the token and account ID as GitHub Actions secrets; never commit them.
- Configure protected GitHub Environment approvals and restrict who can deploy production.
- Configure the Worker name, compatibility date, compatibility flags, environment bindings, and observability settings only after adapter selection.
- Add required Supabase and Stripe environment secrets through the appropriate Cloudflare secret mechanism.
- Keep production and preview credentials separate.
- Verify domain ownership, DNS zone, TLS, redirects, and rollback procedure before changing public traffic.

Never paste API tokens, passwords, service-role keys, Stripe secrets, or customer data into chat, source files, logs, or commits.

## 7. Migration phases and gates

### Phase A — Read-only discovery
- Confirm current production URL, hosting provider, DNS provider, deployment history, and rollback access.
- Audit app routes, server/client boundaries, Node APIs, middleware, image optimization, server actions, file uploads, webhooks, and all environment variables.
- Inspect Supabase schema/RLS and Stripe webhook dependencies.
- Confirm the Cloudflare account, plan, zone, and required access.

### Phase B — Compatibility branch
- Run `npx vinext check` first and record its output; then evaluate the non-destructive `npx vinext init` path in an isolated branch.
- If vinext compatibility fails for required Next.js 15 features, evaluate the documented OpenNext adapter path and its Next.js 15.2 Node.js middleware limitation.
- Add only the selected Cloudflare adapter and Wrangler configuration additively.
- Preserve the existing Next.js app and scripts where possible.
- Add local/workerd preview and type-generation scripts.
- Add GitHub CI checks with no Cloudflare deployment step.
- Verify that secrets are only available at runtime and never exposed to client bundles.

### Phase C — Staging verification
- Deploy one explicitly approved staging version only when local verification is insufficient.
- Test customer and employee authentication, product routes, server APIs, database reads/writes, RLS, Stripe webhook signature handling, uploads, caching, and background jobs.
- Confirm observability, error reporting, and rollback.
- Reconcile actual deployment count and measured performance.

### Phase D — Production cutover
- Obtain explicit production release approval.
- Deploy one known-good commit to Cloudflare.
- Run smoke tests and monitor error rates, latency, auth, data access, and payment webhook delivery.
- Change DNS/custom-domain routing only after the Worker is verified.
- Preserve the previous hosting deployment for rollback until the Cloudflare stability window passes.

### Phase E — Stabilization and retirement
- Reconcile deployment ledger with Cloudflare history.
- Confirm budget enforcement and alerts.
- Remove unused Vercel deployment automation and credentials only after rollback is no longer needed.
- Update operational runbooks and record final production URLs, commit SHA, Cloudflare Worker ID, and DNS state.

## 8. Acceptance criteria

- GitHub remains the authoritative repository and review system.
- Cloudflare Workers runs the application with required Next.js behavior verified.
- No automatic production deployment occurs on ordinary pushes or documentation commits.
- Production deployments require manual dispatch and protected environment approval.
- Deployment ledger is durable, concurrency-safe, reconciled, and blocks at the 400 internal ceiling.
- Total deployments remain below 500 per calendar month.
- Preview deployments are rare, intentional, and counted.
- Customer/employee authentication, catalog, POS, Supabase RLS, Stripe webhook, and existing API behavior pass regression tests.
- DNS is unchanged until production verification and rollback readiness are confirmed.
- No secret is committed or exposed in client output.
- Exact production commit, Cloudflare deployment ID, environment, and smoke-test evidence are recorded.

## 9. Current status and explicit blockers

This document is a migration and deployment-governance plan only. At the audited commit, the repository has no Cloudflare adapter or Wrangler config, and no Cloudflare account connection is available through the current GitHub repository access. No Cloudflare token, account ID, DNS authority, or Cloudflare deployment history was supplied.

Therefore:
- Cloudflare account connection: not verified.
- Runtime adapter/configuration: not implemented.
- GitHub deployment workflow: not implemented.
- Deployment budget counter: not implemented.
- DNS/domain cutover: not performed.
- Production deployment: not performed.

**Do not claim the application has transferred to Cloudflare until the migration phases, acceptance criteria, and post-deployment evidence are complete.**
