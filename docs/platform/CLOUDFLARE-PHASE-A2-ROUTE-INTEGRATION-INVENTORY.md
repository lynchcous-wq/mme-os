# MME OS — Cloudflare Migration Phase A.2: Route & Integration Inventory

**Audit date:** 2026-11-06  
**Audited application commit:** `aadf39502b42c87508f4e8b07d8a4a2cece74eeb`  
**Branch for this audit record:** `platform/cloudflare-phase-a2-integration-inventory`  
**Status:** Read-only findings. No runtime code, SQL, dependencies, secrets, DNS, or deployments changed.

## Repository snapshot

The inspected Git tree at the audited application commit contains 35 tracked files. It includes storefront pages, POS transaction/refund APIs, Stripe refund dispatch and webhook routes, warranty/security dashboard APIs, an internal security-delivery worker, warehouse and warranty pages, a POS authentication helper, Supabase migration/test files, and build documentation. No root lockfile, Wrangler configuration, or Cloudflare adapter was found.

## Customer storefront and identity

- `app/account/page.tsx` renders a “Coming soon” page and describes customer accounts as future work.
- `app/products/page.tsx` says the product catalog is being prepared.
- `app/page.tsx` contains four hard-coded illustrative product records and prices.
- No customer sign-in route or customer authentication implementation appears in this 35-file tree.

**Conclusion:** The inspected storefront snapshot is not a live database-backed customer commerce experience. Navigation links do not prove that customer identity or catalog functionality is implemented.

## POS employee authentication and transaction API

- `lib/pos/authenticated-server.ts` validates a bearer token against Supabase Auth `/auth/v1/user`.
- It resolves the verified Auth subject to an MME person identity using `mme_resolve_person_for_auth_subject`.
- `app/api/pos/transactions/route.ts` accepts only an order ID, requires an `Idempotency-Key`, and calls `mme_pos_create_transaction`.
- A Node contract test exists for POS authentication and transaction API behavior.

Not verified: live credentials, active employee identity mappings, deployed database migrations/RLS, and end-to-end POS transaction execution.

## Stripe refund flow

- The refund dispatcher claims queued work through Supabase RPC, calls Stripe's refund API, and sends an idempotency key.
- The refund webhook validates the Stripe signature over the raw body, checks a five-minute timestamp tolerance and payload size, then calls a Supabase reconciliation RPC.

Not verified: runtime secrets, RPC existence in the connected database, webhook registration, Stripe account mapping, duplicate-event handling, or end-to-end test-mode behavior. Do not treat refunds or payments as production-ready based on source presence alone.

## Warranty/security dashboard and delivery worker

- Dashboard APIs validate bearer tokens through Supabase Auth, check app-metadata roles, and read metrics through service-role RPCs.
- The internal worker checks a shared secret using `timingSafeEqual`, claims jobs from Supabase, and has a correlation path.
- The worker explicitly rejects `notify` jobs with `notification_provider_not_configured` and `reconcile` jobs with `reconciliation_handler_not_configured`. These task types are not implemented in this snapshot.
- The dashboard page stores its access token in browser `sessionStorage`; review this against the threat model and XSS controls before production use.

### Suspected bearer-token regex defect

The source representations of both `app/api/warranty/security-dashboard/route.ts` and `app/api/warranty/security-dashboard/escalate/route.ts` show a bearer-token expression with an extra escaped backslash compared with the working POS helper. This appears likely to match a literal backslash followed by `s`, rather than whitespace. This is a **suspected defect, not a confirmed runtime failure**. Add a focused regression test and reproduce it before changing the routes.

## Cloudflare Workers compatibility

Several API routes explicitly request the Node.js runtime and use `node:crypto`, `Buffer`, HMAC/SHA-256, and timing-safe comparison. The Stripe routes also depend on raw request-body signature verification, external network calls, and idempotent provider operations. The worker route uses Node crypto and Buffer. Every such route needs compatibility validation against the selected Cloudflare Next.js adapter and runtime. No adapter or Wrangler config exists in this snapshot.

## Test and dependency readiness

- `package.json` defines `lint` as `tsc --noEmit`; a test script is not present in the inspected package manifest.
- Node contract tests exist, but no deterministic lockfile was found and no test execution was performed.
- The financial-management test references a route, page, and migration not present in the inspected 35-file tree. It appears out of sync with this exact commit.
- No dependency install, typecheck, test suite, adapter check, or production build was executed.

## Required next gates

1. Reproduce the suspected dashboard bearer-token regex issue with a focused test; only then patch both routes and add regression coverage.
2. Implement or explicitly disable unsupported worker task types before calling them operational.
3. Align tests with files present on the target branch.
4. Add a deterministic lockfile and explicit test command; run typecheck, tests, and production build on the exact candidate commit.
5. Inventory environment-variable names and client/server usage without reading or printing secret values.
6. Run Cloudflare compatibility checks on the complete candidate branch, including Node APIs, raw webhook bodies, and external fetch behavior.
7. Keep DNS and production deployments unchanged until every gate passes.

## Release status

Audit record only. No application code changed, no CI or adapter added, no secrets accessed, no DNS changed, and no deployment performed.
