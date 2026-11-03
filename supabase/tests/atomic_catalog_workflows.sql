-- Run after applying 20261103000600_atomic_catalog_workflows.sql.
-- These checks verify the transaction entry points and grants; behavior tests
-- still require an isolated Supabase/PostgreSQL test project with seeded users.
do $$
declare
  v_name text;
  v_def text;
  v_security_definer boolean;
  v_service_granted boolean;
  v_authenticated_granted boolean;
begin
  foreach v_name in array array[
    'mme_catalog_return_for_correction(uuid,uuid,text)',
    'mme_catalog_approve_product(uuid,uuid)',
    'mme_catalog_publish_product(uuid,uuid)',
    'mme_catalog_revise_returned_product(uuid,uuid,integer,jsonb)'
  ] loop
    select pg_get_functiondef(p.oid), p.prosecdef
      into v_def, v_security_definer
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.oid=v_name::regprocedure;
    if not found then raise exception 'Atomic workflow function missing: %',v_name; end if;
    if not v_security_definer then raise exception 'Atomic workflow must be SECURITY DEFINER: %',v_name; end if;
    if position('product_catalog_events' in v_def)=0 then
      raise exception 'Atomic workflow must write catalog audit events: %',v_name;
    end if;
    select has_function_privilege('service_role',v_name,'EXECUTE') into v_service_granted;
    if not v_service_granted then raise exception 'service_role execute grant missing: %',v_name; end if;
    select has_function_privilege('authenticated',v_name,'EXECUTE') into v_authenticated_granted;
    if v_authenticated_granted then raise exception 'authenticated must not execute atomic workflow directly: %',v_name; end if;
  end loop;

  select pg_get_functiondef('public.mme_catalog_revise_returned_product(uuid,uuid,integer,jsonb)'::regprocedure)
    into v_def;
  if position('product_catalog_revisions' in v_def)=0 then
    raise exception 'Revision workflow must write immutable revision snapshot';
  end if;
  if position('for update' in lower(v_def))=0 then
    raise exception 'Revision workflow must lock product row';
  end if;
end;
$$;
