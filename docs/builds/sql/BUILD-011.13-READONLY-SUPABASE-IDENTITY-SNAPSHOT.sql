-- MME OS Build 011.13 — READ-ONLY Supabase identity/schema snapshot
-- Run in the SQL Editor for the exact MME project/environment.
-- This file contains SELECT statements only. It does not mutate schema or data.
-- Do not export auth.users, passwords, tokens, recovery codes, or customer PII.

-- 1) Confirm whether the Supabase migration ledger exists and inspect its columns.
select table_schema, table_name, column_name, data_type
from information_schema.columns
where table_schema = 'supabase_migrations'
  and table_name = 'schema_migrations'
order by ordinal_position;

-- 2) If the ledger exists, inspect applied versions.
-- If this statement errors because the ledger/table is absent, do not create it.
select version
from supabase_migrations.schema_migrations
order by version;

-- 3) Inventory relevant public tables and columns.
select
  table_schema, table_name, ordinal_position, column_name,
  data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and (
    table_name ilike '%person%'
    or table_name ilike '%identity%'
    or table_name ilike '%customer%'
    or table_name ilike '%employee%'
    or table_name ilike '%role%'
    or table_name ilike '%permission%'
    or table_name ilike '%audit%'
    or table_name ilike '%order%'
    or table_name ilike '%cart%'
    or table_name ilike '%inventory%'
    or table_name ilike '%session%'
  )
order by table_name, ordinal_position;

-- 4) Primary keys, unique constraints, foreign keys, and check constraints.
select
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_name as referenced_table,
  ccu.column_name as referenced_column
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
    or tc.table_name ilike '%audit%'
  )
order by tc.table_name, tc.constraint_name, kcu.ordinal_position;

-- 5) RLS enabled/forced status.
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r','p')
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

-- 6) RLS policies. Review expressions for tenant/person scoping and write restrictions.
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

-- 7) Relevant functions/RPC signatures and security properties.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as result_type,
  p.prosecdef as security_definer,
  p.proconfig as function_settings,
  pg_get_userbyid(p.proowner) as owner
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

-- 8) Function EXECUTE grants for relevant functions.
select
  routine_schema, routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and (
    routine_name ilike '%person%'
    or routine_name ilike '%identity%'
    or routine_name ilike '%authoriz%'
    or routine_name ilike '%customer%link%'
    or routine_name ilike '%employee%permission%'
  )
order by routine_name, grantee, privilege_type;

-- 9) Relevant table grants.
select
  table_schema, table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and (
    table_name ilike '%person%'
    or table_name ilike '%identity%'
    or table_name ilike '%customer%'
    or table_name ilike '%employee%'
    or table_name ilike '%role%'
    or table_name ilike '%permission%'
    or table_name ilike '%audit%'
  )
order by table_name, grantee, privilege_type;

-- 10) Duplicate migration versions in the repository are documented separately.
-- This query detects duplicate versions in a target ledger only if the ledger
-- schema allows duplicates (normally it should not); a primary-key ledger may
-- prevent such duplicates by design.
select version, count(*) as occurrences
from supabase_migrations.schema_migrations
group by version
having count(*) > 1
order by version;
