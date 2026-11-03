# Local Supabase Development

MME OS now includes a local Supabase configuration so the database foundation can be tested without creating or connecting a hosted project.

## Prerequisites

- Docker Desktop (running)
- Supabase CLI
- Node.js version compatible with the repository

## Start a disposable local environment

From the repository root:

```bash
supabase start
```

The CLI prints local API, database, Studio, and local development keys. Use only those local values in a developer-only `.env.local` file. Never commit `.env.local`, and never copy a hosted production service-role key into local development.

## Apply migrations and reset test data

```bash
supabase db reset
```

This recreates the local database and applies migrations in order. It is destructive to the local database, which is intentional for repeatable tests. It does not connect to a hosted project unless the CLI has been explicitly linked and a remote command is used; do not run `supabase link`, `supabase db push`, or any remote command for this local verification step.

## Run SQL structural tests

```bash
supabase test db
```

If the CLI does not discover the repository's SQL test files automatically, run each SQL file through local Studio's SQL editor against the local database:

- `supabase/tests/product_catalog_foundation.sql`
- `supabase/tests/employee_access_control.sql`
- `supabase/tests/employee_authorization_engine.sql`
- `supabase/tests/atomic_catalog_workflows.sql`

## Run application checks

```bash
npm install
npm run check:migrations
npm run check:catalog-api-security
npm run lint
npm run build
```

Set the local Supabase URL, publishable/anon key, and local service-role key in `.env.local` only. The service-role key must remain server-only.

## What local success means

A successful local reset and SQL test run verifies migration application and structural assertions in the local disposable database. It does not verify production configuration, hosted authentication email delivery, domain redirects, Stripe, live payment capture, shipping, or production deployment.

Keep the CEO identity unprovisioned until the account is independently verified and a controlled provisioning procedure is approved. Do not create a production employee or customer account as part of local setup.
