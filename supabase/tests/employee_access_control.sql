-- Manual verification for 20261103000200_employee_access_control.sql.
-- Run only against a disposable/test Supabase project after applying the migration.
-- This script checks structure and fail-closed defaults; it does not create users.

do $$
declare
  table_name text;
  rls_enabled boolean;
  rls_forced boolean;
  policy_count integer;
  ceo_id uuid;
  access_frozen boolean;
begin
  foreach table_name in array array[
    'employee_relationships',
    'employee_permission_grants',
    'employee_security_settings',
    'employee_access_audit_events'
  ] loop
    select c.relrowsecurity, c.relforcerowsecurity
      into rls_enabled, rls_forced
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = table_name;

    if coalesce(rls_enabled, false) is not true
       or coalesce(rls_forced, false) is not true then
      raise exception 'RLS and FORCE RLS must both be enabled on public.%', table_name;
    end if;

    select count(*) into policy_count
      from pg_policies
     where schemaname = 'public'
       and tablename = table_name;

    if policy_count <> 0 then
      raise exception 'Unexpected direct RLS policies on public.%; keep access fail-closed until reviewed', table_name;
    end if;
  end loop;

  select ceo_user_id, employee_access_frozen
    into ceo_id, access_frozen
    from public.employee_security_settings
   where singleton = true;

  if not found or ceo_id is not null or access_frozen is not false then
    raise exception 'CEO control must start unprovisioned and unfrozen; privileged access must fail closed';
  end if;

  if not exists (
    select 1 from pg_trigger
     where tgname = 'employee_access_audit_no_update_delete'
       and not tgisinternal
  ) then
    raise exception 'Append-only employee access audit trigger is missing';
  end if;

  if not exists (
    select 1 from pg_trigger
     where tgname = 'employee_relationships_updated_at'
       and not tgisinternal
  ) then
    raise exception 'Employee relationship updated_at trigger is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.employee_relationships'::regclass
       and conname = 'employee_relationships_check'
  ) then
    -- Constraint names may be generated differently; check the expression below instead.
    if not exists (
      select 1 from pg_constraint
       where conrelid = 'public.employee_relationships'::regclass
         and pg_get_constraintdef(oid) like '%terminated_at%'
    ) then
      raise exception 'Employee termination timestamp constraint is missing';
    end if;
  end if;
end;
$$;

-- Expected result: DO completes without exception.
-- A null CEO identity means no privileged catalog approval can be authorized.
-- Never run provisioning or permission grants from a browser/client context.
