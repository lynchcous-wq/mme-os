-- Run after applying migrations 20261103000600 through 20261103000800.
-- Structural checks only; behavioral rollback/concurrency tests require a test database.
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
    'mme_catalog_revise_returned_product(uuid,uuid,integer,jsonb)',
    'mme_catalog_submit_product(uuid,uuid)',
    'mme_catalog_create_product_draft(uuid,jsonb)'
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
    if position('for update' in lower(v_def))=0 and v_name <> 'mme_catalog_create_product_draft(uuid,jsonb)' then
      raise exception 'State transition workflow must lock product row: %',v_name;
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

  select pg_get_functiondef('public.mme_catalog_create_product_draft(uuid,jsonb)'::regprocedure)
    into v_def;
  if position('product_media' in v_def)=0 then
    raise exception 'Draft creation must attach optional media metadata atomically';
  end if;
  if position('catalog.create' in v_def)=0 then
    raise exception 'Draft creation must authorize catalog.create';
  end if;

  select pg_get_functiondef('public.mme_catalog_publish_product(uuid,uuid)'::regprocedure)
    into v_def;
  if position('product_id' in v_def)=0 or position('catalog.approve' in v_def)=0 then
    raise exception 'Publication must validate approver grant scope';
  end if;
end;
$$;
