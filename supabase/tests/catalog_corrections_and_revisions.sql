begin;
select plan(0);
-- Run only after applying 20261103000500_catalog_corrections_and_revisions.sql
do $$
declare
  v_status_check boolean;
  v_notes_column boolean;
  v_revisions_rls boolean;
  v_revisions_force_rls boolean;
  v_immutable_trigger boolean;
begin
  select exists (
    select 1 from pg_constraint
    where conrelid = 'public.products'::regclass
      and conname = 'products_catalog_status_check'
      and pg_get_constraintdef(oid) like '%changes_requested%'
  ) into v_status_check;
  if not v_status_check then raise exception 'changes_requested status constraint missing'; end if;

  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='products' and column_name='correction_notes'
  ) into v_notes_column;
  if not v_notes_column then raise exception 'correction_notes column missing'; end if;

  select relrowsecurity, relforcerowsecurity
    into v_revisions_rls, v_revisions_force_rls
    from pg_class where oid='public.product_catalog_revisions'::regclass;
  if not v_revisions_rls or not v_revisions_force_rls then raise exception 'revision RLS must be enabled and forced'; end if;

  select exists (
    select 1 from pg_trigger
    where tgrelid='public.product_catalog_revisions'::regclass
      and tgname='product_catalog_revisions_no_update_delete'
      and not tgisinternal
  ) into v_immutable_trigger;
  if not v_immutable_trigger then raise exception 'revision immutability trigger missing'; end if;
end;
$$;

select * from finish();
rollback;
