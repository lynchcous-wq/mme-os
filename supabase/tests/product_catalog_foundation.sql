begin;
select plan(1);
-- Manual database verification for 20261103000100_product_catalog.sql.
-- Run only against a disposable/test Supabase project after applying the migration.
-- This file is a verification script; it does not apply migrations or create test data.

select lives_ok($test$ do $do$
declare
  table_name text;
  rls_enabled boolean;
  policy_count integer;
  category_count integer;
  version_function text;
begin
  foreach table_name in array array[
    'product_categories',
    'products',
    'product_media',
    'product_catalog_events'
  ] loop
    select c.relrowsecurity
      into rls_enabled
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = table_name;

    if coalesce(rls_enabled, false) is not true then
      raise exception 'RLS is not enabled on public.%', table_name;
    end if;

    select count(*)
      into policy_count
      from pg_policies
     where schemaname = 'public'
       and tablename = table_name;

    if policy_count <> 0 then
      raise exception 'Unexpected RLS policies on public.%; review before enabling access', table_name;
    end if;
  end loop;

  select count(*) into category_count
    from public.product_categories
   where slug in (
     'televisions','laptops','tablets','cellphones','smartwatches',
     'accessories','audio','gaming','smart-home','services-subscriptions'
   );

  if category_count <> 10 then
    raise exception 'Expected 10 seeded catalog categories; found %', category_count;
  end if;

  select pg_get_functiondef('public.mme_catalog_products_set_updated_at()'::regprocedure)
    into version_function;

  if position('new.version = old.version + 1' in version_function) = 0 then
    raise exception 'Product version increment trigger is missing';
  end if;

  if not exists (
    select 1 from pg_trigger
     where tgname = 'product_catalog_events_no_update_delete'
       and not tgisinternal
  ) then
    raise exception 'Append-only catalog event trigger is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.products'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%condition%'
       and pg_get_constraintdef(oid) ilike '%inspection_required%'
       and pg_get_constraintdef(oid) ilike '%parts_only%'
  ) then
    raise exception 'Product condition allowlist constraint is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.products'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%tracking_mode%'
       and pg_get_constraintdef(oid) ilike '%serialized%'
       and pg_get_constraintdef(oid) ilike '%quantity%'
  ) then
    raise exception 'Product tracking mode allowlist constraint is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.products'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%catalog_status%'
       and pg_get_constraintdef(oid) ilike '%pending_approval%'
       and pg_get_constraintdef(oid) ilike '%published%'
  ) then
    raise exception 'Product catalog status allowlist constraint is missing';
  end if;
end;
$do$; $test$, 'product catalog foundation security and integrity checks pass');

-- Expected result: DO completes without exception.
-- RLS remains closed by default until reviewed role-specific policies are deployed.

select * from finish();
rollback;
