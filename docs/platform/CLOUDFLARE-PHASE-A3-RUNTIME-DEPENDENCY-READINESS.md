# MME OS — Cloudflare Migration Phase A.3: Runtime & Dependency Readiness

**Audit date:** 2026-11-06  
**Application baseline:** `85f77b90339fe73a9668f648f5b8cc7d2a8df05e`  
**Branch:** `platform/cloudflare-phase-a3-runtime-readiness`  
**Scope:** Static inspection of tracked package, config, route, and test files. No secret values were accessed. No application code, dependency manifests, lockfiles, DNS, or deployment settings were changed.

## 1. Dependency baseline

The inspected `package.json` declares:
- `next: ^15.2.4`
- `react: ^19.0.0`
- `react-dom: ^19.0.0`
- TypeScript and Node/React type packages as development dependencies.

The inspected manifest does not declare Supabase or Stripe SDK packages; inspected server routes currently call Supabase REST/Auth and Stripe HTTP APIs directly. This is not inherently a problem, but means runtime compatibility depends on fetch, Web APIs, and selected Node built-ins rather than SDK adapter support.

No `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, or `npm-shrinkwrap.json` is present in the audited tree. A reproducible dependency install cannot be established from this snapshot.

## 2. Scripts and test coverage

Manifest scripts:
- `dev`: `next dev`
- `build`: `next build`
- `start`: `next start`
- `lint`: `tsc --noEmit`

There is no `test` script. Four Node contract-test files are tracked, but test paths are inconsistent with the audited tree:
- `build010-executive-command-center.test.mjs` imports executive command-center page/API files not present in the 35-file tree.
- `build010-financial-management.test.mjs` imports a financial-management migration, API, and page not present in the tree.
- `build010-notification-acknowledgement-sla.test.mjs` imports notification-routing API and worker paths not present in the tree.
- The POS contract test references files that are present.

This strongly indicates the test collection and inspected application snapshot are out of sync. No test, TypeScript check, install, or production build was run in this audit environment.

## 3. Runtime and framework configuration

- Next config only sets `poweredByHeader: false`.
- TypeScript is strict, no-emit, ESNext module/bundler resolution, and includes all `*.ts` / `*.tsx`.
- No Wrangler configuration or Cloudflare adapter exists in the inspected tree.
- No root middleware file exists.
- No environment example file exists.
- No CI workflow was found in the inspected tree.
- The app has several routes that explicitly set `runtime = "nodejs"` and import `node:crypto`; webhook and worker handlers also use `Buffer`.

Do not switch these routes to the Workers runtime until the selected adapter's Node compatibility support is tested on the complete app.

## 4. Environment-variable name inventory

Static source references found in the inspected routes/helpers:
- `MME_POS_REFUND_WORKER_SECRET`
- `STRIPE_SECRET_KEY`
- `SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `MME_SECURITY_WORKER_SECRET`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_ANON_KEY`

This is a partial inventory of the tracked source files, not proof that it covers every deployment environment or untracked feature branch. The `NEXT_PUBLIC_` variables are exposed to browser bundles by Next.js convention; only public Supabase URL/anon key values should use that prefix. Service-role, Stripe, and worker secrets must remain server-only. Do not place secret values in Git, client code, build artifacts, or chat.

The current routes do not consistently use one Supabase URL variable name: some prefer `SUPABASE_URL` with public fallback, while the security worker uses `NEXT_PUBLIC_SUPABASE_URL` only. Standardize server-side configuration in a later reviewed change, without changing existing production values until mapped.

## 5. Static security/readiness findings

1. Both warranty dashboard route files contain the suspicious regex `/^Bearer\\\\s+(.+)$/i` in source text, while the POS helper uses `/^Bearer\\s+([A-Za-z0-9._~-]+)$/i`. The dashboard pattern likely rejects ordinary bearer headers. Treat this as a confirmed source-level mismatch; runtime reproduction and regression coverage remain required before a fix.
2. The security-delivery worker's `notify` and `reconcile` tasks intentionally fail with provider/handler-not-configured errors in this snapshot.
3. The POS refund dispatcher is a privileged worker endpoint protected by `MME_POS_REFUND_WORKER_SECRET`; it calls Stripe live API when configured. Use only Stripe test mode in staging and do not invoke dispatch until test data, account mapping, and safe worker auth are established.
4. The webhook requires raw-body signature verification. Any Cloudflare adapter must preserve raw request body bytes and header semantics.
5. The source uses Node crypto, Buffer, and `AbortSignal.timeout`; compatibility must be validated route by route.

## 6. Cloudflare path decision

**Decision: adapter selection remains blocked.**

The current snapshot is Next.js 15.2.4 with React 19 and has no lockfile, no CI, and several Node-runtime routes. Do not assume vinext or OpenNext is drop-in compatible. On an isolated compatibility branch:
1. establish a lockfile using the repository's chosen package manager;
2. run a clean install, `tsc --noEmit`, and the repaired contract suite;
3. run the Next.js production build;
4. test the current Cloudflare-recommended Next.js path against this exact version;
5. if the preferred path cannot support the required behavior, separately test `@opennextjs/cloudflare`;
6. verify Node API compatibility, webhook raw-body verification, route caching/dynamic behavior, environment bindings, and Supabase/Stripe outbound calls.

Do not combine a Next.js major upgrade with the hosting migration without explicit approval.

## 7. Next gates

- Reconcile the actual target application branch/build with this inspected snapshot before choosing a baseline.
- Add a deterministic lockfile and explicit `test` script only after confirming the intended package manager.
- Repair or re-scope stale tests so every imported file exists on the candidate branch.
- Add a minimal non-secret `.env.example` only after the full env inventory is complete.
- Reproduce and fix the dashboard bearer-token parsing defect with regression tests.
- Decide and implement the missing notification/reconciliation handlers or disable those task types safely.
- Run install, typecheck, tests, production build, and adapter compatibility tests in CI.
- Keep production DNS, live Stripe behavior, and production deployments unchanged until all gates pass.

## 8. Status

This commit records static audit findings only. No dependency installation, lockfile generation, code changes, test execution, Cloudflare configuration, secret access, DNS change, or deployment occurred.
