-- Build 011.01 — read-only Supabase schema audit
-- Run in the Supabase SQL Editor using a role authorized to inspect schema metadata.
-- This script performs SELECTs only. It does not read customer/employee row data,
-- change schema, alter permissions, or apply migrations.

-- 1) Applied Supabase migration history (if the standard ledger exists).
select table_schema, table_name
from information_schema.tables
where table_schema = 'supabase_migrations'
  and table_name = 'schema_migrations';

select version, name
from supabase_migrations.schema_migrations
order by version;

-- 2) Procurement, vendor, product, receiving, stock and identity table inventory.
select
  c.table_schema,
  c.table_name,
  c.column_name,
  c.data_type,
  c.udt_name,
  c.is_nullable,
  c.column_default
from information_schema.columns c
where c.table_schema = 'public'
  and (
    c.table_name ilike '%vendor%'
    or c.table_name ilike '%supplier%'
    or c.table_name ilike '%catalog%'
    or c.table_name ilike '%purchase%'
    or c.table_name ilike '%procure%'
    or c.table_name ilike '%receiv%'
    or c.table_name ilike '%inventory%'
    or c.table_name ilike '%stock%'
    or c.table_name ilike '%product%'
    or c.table_name ilike '%location%'
    or c.table_name ilike '%person_identity%'
    or c.table_name ilike '%employee%'
    or c.table_name ilike '%role%'
  )
order by c.table_name, c.ordinal_position;

-- 3) Foreign-key dependencies for the same subject area.
select
  tc.table_name,
  kcu.column_name,
  ccu.table_name as foreign_table_name,
  ccu.column_name as foreign_column_name,
  rc.update_rule,
  rc.delete_rule,
  tc.constraint_name
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_schema = kcu.constraint_schema
 and tc.constraint_name = kcu.constraint_name
join information_schema.constraint_column_usage ccu
  on ccu.constraint_schema = tc.constraint_schema
 and ccu.constraint_name = tc.constraint_name
join information_schema.referential_constraints rc
  on rc.constraint_schema = tc.constraint_schema
 and rc.constraint_name = tc.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'
  and (
    tc.table_name ilike '%vendor%' or tc.table_name ilike '%supplier%'
    or tc.table_name ilike '%catalog%' or tc.table_name ilike '%purchase%'
    or tc.table_name ilike '%procure%' or tc.table_name ilike '%receiv%'
    or tc.table_name ilike '%inventory%' or tc.table_name ilike '%stock%'
    or tc.table_name ilike '%product%' or tc.table_name ilike '%location%'
    or ccu.table_name ilike '%vendor%' or ccu.table_name ilike '%supplier%'
    or ccu.table_name ilike '%inventory%' or ccu.table_name ilike '%product%'
    or ccu.table_name ilike '%location%'
  )
order by tc.table_name, tc.constraint_name;

-- 4) Primary, unique, check and exclusion constraints.
select
  tc.table_name,
  tc.constraint_type,
  tc.constraint_name,
  cc.check_clause
from information_schema.table_constraints tc
left join information_schema.check_constraints cc
  on cc.constraint_schema = tc.constraint_schema
 and cc.constraint_name = tc.constraint_name
where tc.table_schema = 'public'
  and (
    tc.table_name ilike '%vendor%' or tc.table_name ilike '%supplier%'
    or tc.table_name ilike '%catalog%' or tc.table_name ilike '%purchase%'
    or tc.table_name ilike '%procure%' or tc.table_name ilike '%receiv%'
    or tc.table_name ilike '%inventory%' or tc.table_name ilike '%stock%'
    or tc.table_name ilike '%product%' or tc.table_name ilike '%location%'
  )
order by tc.table_name, tc.constraint_type, tc.constraint_name;

-- 5) RLS enabled/forced state.
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
    c.relname ilike '%vendor%' or c.relname ilike '%supplier%'
    or c.relname ilike '%catalog%' or c.relname ilike '%purchase%'
    or c.relname ilike '%procure%' or c.relname ilike '%receiv%'
    or c.relname ilike '%inventory%' or c.relname ilike '%stock%'
    or c.relname ilike '%product%' or c.relname ilike '%location%'
  )
order by c.relname;

-- 6) RLS policies and role grants.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and (
    tablename ilike '%vendor%' or tablename ilike '%supplier%'
    or tablename ilike '%catalog%' or tablename ilike '%purchase%'
    or tablename ilike '%procure%' or tablename ilike '%receiv%'
    or tablename ilike '%inventory%' or tablename ilike '%stock%'
    or tablename ilike '%product%' or tablename ilike '%location%'
  )
order by tablename, policyname;

select
  table_name,
  grantee,
  privilege_type,
  is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and (
    table_name ilike '%vendor%' or table_name ilike '%supplier%'
    or table_name ilike '%catalog%' or table_name ilike '%purchase%'
    or table_name ilike '%procure%' or table_name ilike '%receiv%'
    or table_name ilike '%inventory%' or table_name ilike '%stock%'
    or table_name ilike '%product%' or table_name ilike '%location%'
  )
order by table_name, grantee, privilege_type;

-- 7) Relevant function definitions and security properties.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  p.prosecdef as security_definer,
  p.proconfig as function_settings,
  pg_get_userbyid(p.proowner) as owner,
  pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (
    p.proname ilike '%purchase%' or p.proname ilike '%procure%'
    or p.proname ilike '%receiv%' or p.proname ilike '%inventory%'
    or p.proname ilike '%stock%' or p.proname ilike '%vendor%'
  )
order by p.proname, arguments;

-- End of read-only audit. Export result sets for Build 011.01 review.
