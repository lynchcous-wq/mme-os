# Build 011.12 — Supabase Schema Preflight & Migration Compatibility

Status: **repository migration inventory completed; live Supabase state remains unverified**.
Branch: `implementation/build-011-12-supabase-schema-preflight`.
Base: `implementation/build-011-11-identity-migration-reconciliation`.
Date: 2026-11-08.

## Executive result

The repository inventory now shows a much larger migration lineage on `implementation/build-010-84-identity-review-dashboard` than on the active Build 011 purchasing/receiving branch.

- The Build 010.84 branch contains a broad migration sequence covering catalog, inventory, POS, Stripe refunds, customer portal, warranty/security, identity and workforce functions.
- The active Build 011 purchasing/receiving branch and the Build 011.11 branch contain only one file under `supabase/migrations/`: `20261105001800_build010_warranty_security_operations_dashboard.sql`.
- Therefore, the Build 011 branch does **not** contain the earlier identity bridge migrations or the wider prerequisite schema lineage in its current checked-in migration directory.
- The repository tree cannot prove what has been applied to the live Supabase project. No Supabase database connector or authorized SQL execution/read-only project connection is available in this work session.

Do not run migrations from either branch until the target project's migration ledger and schema are inspected.

## 1. Verified repository inventory

### Build 011 branches

Inspected:
- `implementation/build-011-purchasing-receiving-integration`
- `implementation/build-011-10-authentication-consolidation`

Each tree contains one migration file:
- `supabase/migrations/20261105001800_build010_warranty_security_operations_dashboard.sql`

### Build 010.84 branch

Inspected:
- `implementation/build-010-84-identity-review-dashboard`

The branch contains a large migration sequence, including:
- Build 001 catalog, inventory, orders, reservations and serialized-device workflows.
- Build 004 person/login identity bridge migrations:
  - `20261103008400_build004_person_login_identity_bridge.sql`
  - `20261103008420_build004_identity_privilege_hardening.sql`
  - `20261103008430_build004_person_keyed_authorization.sql`
  - `20261103008440_build004_require_active_person_identity.sql`
- Build 009 POS, tender, refund, Stripe refund settlement, inventory and customer order portal migrations.
- Build 010 identity governance and customer identity linking/review migrations.
- Build 010 workforce, HR, payroll, purchasing, warehouse, CRM and notification migrations.

This confirms the active Build 011 branch is not a full migration superset of the earlier Build 010.84 branch. It is a source-tree inventory finding, not a production schema finding.

## 2. Newly confirmed duplicate migration versions

The Build 010.84 branch contains at least two duplicate migration version prefixes:

| Version | First file | Conflicting file |
|---|---|---|
| `20261106004000` | `build010_customer_identity_link_requests.sql` | `build010_employee_lifecycle_hr_administration.sql` |
| `20261106005000` | `build010_customer_identity_review_dashboard.sql` | `build010_vendor_catalog_price_intelligence.sql` |

Supabase migration version identifiers must be unique. These collisions must be reconciled before packaging a clean migration sequence.

Do not rename any migration that may already have been applied to a shared/production database until the actual migration ledger has been inspected. If neither conflicting version has been applied, assign unique unused versions preserving dependency order and update any manifest/test references. If either is already applied, preserve the recorded version and create a forward-only migration strategy.

## 3. Required owner-run read-only snapshot

The following SQL is intended for the Supabase SQL Editor in the exact project/environment used by MME OS. It is read-only. Run it in staging first if the production project cannot be safely inspected. Return results with secrets and personal data omitted.

### 3.1 Migration history

```sql
select version
from supabase_migrations.schema_migrations
order by version;
```

If the migration table is unavailable or named differently, do not create it; report the error and inspect the project's migration management configuration.

### 3.2 Relevant tables and columns

```sql
select
  table_schema,
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and (
    table_name ilike '%person%'
    or table_name ilike '%identity%'
    or table_name ilike '%customer%relationship%'
    or table_name ilike '%customer%account%'
    or table_name ilike '%employee%relationship%'
    or table_name ilike '%employee%permission%'
    or table_name ilike '%role%'
    or table_name ilike '%permission%'
    or table_name ilike '%audit%'
    or table_name ilike '%order%'
    or table_name ilike '%cart%'
    or table_name ilike '%inventory%'
  )
order by table_name, ordinal_position;
```

### 3.3 RLS state and policies

```sql
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and (
    c.relname ilike '%person%'
    or c.relname ilike '%identity%'
    or c.relname ilike '%customer%'
    or c.relname ilike '%employee%'
    or c.relname ilike '%role%'
    or c.relname ilike '%permission%'
    or c.relname ilike '%audit%'
  )
order by c.relname;

select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and (
    tablename ilike '%person%'
    or tablename ilike '%identity%'
    or tablename ilike '%customer%'
    or tablename ilike '%employee%'
    or tablename ilike '%role%'
    or tablename ilike '%permission%'
    or tablename ilike '%audit%'
  )
order by tablename, policyname;
```

### 3.4 Functions and identity RPC signatures

```sql
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as result_type,
  p.prosecdef as security_definer,
  p.proconfig as function_settings
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (
    p.proname ilike '%person%'
    or p.proname ilike '%identity%'
    or p.proname ilike '%authoriz%'
    or p.proname ilike '%customer%link%'
    or p.proname ilike '%employee%permission%'
  )
order by p.proname;
```

### 3.5 Constraints and foreign-key dependencies

```sql
select
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_name as foreign_table_name,
  ccu.column_name as foreign_column_name
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
  on tc.constraint_schema = kcu.constraint_schema
 and tc.constraint_name = kcu.constraint_name
left join information_schema.constraint_column_usage ccu
  on tc.constraint_schema = ccu.constraint_schema
 and tc.constraint_name = ccu.constraint_name
where tc.constraint_schema = 'public'
  and (
    tc.table_name ilike '%person%'
    or tc.table_name ilike '%identity%'
    or tc.table_name ilike '%customer%'
    or tc.table_name ilike '%employee%'
    or tc.table_name ilike '%role%'
    or tc.table_name ilike '%permission%'
  )
order by tc.table_name, tc.constraint_name, kcu.ordinal_position;
```

### 3.6 Auth provider settings

Do not query or export password hashes, access tokens, refresh tokens, email contents, recovery codes or other credentials. Review Auth providers, redirect allowlist, email confirmation, MFA and session settings through the Supabase Dashboard UI. Report only enabled/disabled settings and non-secret configuration status.

## 4. Migration selection and compatibility rules

1. Compare the target migration ledger to the candidate branch migration files by exact version, not just filename.
2. Identify whether the early Build 004 matrix lineage, later person/login bridge, or neither is present in the target database.
3. If the early matrix schema exists, do not run the later bridge's same-named `CREATE TABLE` migrations unchanged. Prepare a forward-only compatibility migration after schema review.
4. If the later person/login bridge exists, verify every dependent table, RPC, trigger, policy, grant and function signature before continuing.
5. If neither identity lineage exists, stage the full dependency chain from the selected canonical branch and resolve duplicate migration versions before applying anything.
6. Do not copy only the four identity bridge migrations into Build 011: they depend on employee, catalog and authorization objects created by earlier migrations.
7. Reconcile all migration consumers in application code, including POS authentication, employee permission checks, customer account linking, customer portal and identity review.
8. Preserve production data. Never auto-link accounts by email alone. Any backfill requires explicit matching rules, duplicate detection, review and audit.
9. Keep the early matrix branch as historical evidence, not as a second schema to install.
10. Apply to a disposable staging project first; production rollout requires an approved backup, reviewed forward migration and verification plan.

## 5. Build 011.12 completion status

- [x] Repository migration inventory compared across Build 011 and Build 010.84.
- [x] Confirmed Build 011 branch migration directory is incomplete relative to the earlier Build 010.84 lineage.
- [x] Identified duplicate migration version `20261106004000`.
- [x] Identified additional duplicate migration version `20261106005000`.
- [x] Prepared read-only SQL snapshot queries for the project owner.
- [ ] Read actual Supabase migration ledger.
- [ ] Read actual schema, policies, functions and grants.
- [ ] Confirm active Supabase project/environment and Auth settings.
- [ ] Compare live state with candidate migrations.
- [ ] Produce an additive compatibility migration from verified state.
- [ ] Run staging migration and auth/RLS integration tests.

## 6. Current disposition

Build 011.12 completes the repository-side preflight and prepares the owner-run read-only schema snapshot. It does **not** claim live Supabase verification, does not apply SQL, does not modify users or data, and does not deploy to Vercel.

The next step is to provide the redacted outputs from sections 3.1–3.5 and the non-secret Auth configuration summary. Only then can the exact compatibility migration be authored safely. If a connected Supabase project integration is made available, perform the same inspection directly and keep it read-only until the migration plan is approved.
