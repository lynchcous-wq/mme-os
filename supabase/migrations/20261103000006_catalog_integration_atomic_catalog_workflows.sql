begin;

create or replace function public.mme_catalog_return_for_correction(
  p_actor_user_id uuid, p_product_id uuid, p_correction_notes text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_product public.products%rowtype;
begin
  if length(btrim(coalesce(p_correction_notes,''))) < 10 or length(p_correction_notes) > 2000 then
    raise exception 'Correction notes must be between 10 and 2,000 characters' using errcode='22023';
  end if;
  if not public.mme_employee_authorize_catalog_action(p_actor_user_id,'catalog.return',p_product_id,null) then
    raise exception 'Catalog return permission denied' using errcode='42501';
  end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found or v_product.catalog_status <> 'pending_approval' or v_product.approved_by is not null then
    raise exception 'Product is no longer awaiting review' using errcode='40001';
  end if;
  if v_product.created_by = p_actor_user_id then
    raise exception 'Submitter cannot review their own product' using errcode='42501';
  end if;
  update public.products set catalog_status='changes_requested', correction_notes=btrim(p_correction_notes),
    returned_by=p_actor_user_id, returned_at=now()
  where id=p_product_id returning * into v_product;
  insert into public.product_catalog_events(product_id,event_type,actor_id,product_version,event_data)
  values(v_product.id,'changes_requested',p_actor_user_id,v_product.version,
    jsonb_build_object('correction_notes',btrim(p_correction_notes)));
  return jsonb_build_object('id',v_product.id,'sku',v_product.sku,'name',v_product.name,
    'catalog_status',v_product.catalog_status,'correction_notes',v_product.correction_notes,'version',v_product.version);
end;
$$;

create or replace function public.mme_catalog_approve_product(
  p_actor_user_id uuid, p_product_id uuid
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_product public.products%rowtype;
begin
  if not public.mme_employee_authorize_catalog_action(p_actor_user_id,'catalog.approve',p_product_id,null) then
    raise exception 'Catalog approval permission denied' using errcode='42501';
  end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found or v_product.catalog_status <> 'pending_approval' or v_product.approved_by is not null then
    raise exception 'Product is no longer awaiting approval' using errcode='40001';
  end if;
  if v_product.created_by = p_actor_user_id then
    raise exception 'Submitter cannot approve their own product' using errcode='42501';
  end if;
  update public.products set approved_by=p_actor_user_id, approved_at=now()
  where id=p_product_id returning * into v_product;
  insert into public.product_catalog_events(product_id,event_type,actor_id,product_version,event_data)
  values(v_product.id,'approved',p_actor_user_id,v_product.version,'{}'::jsonb);
  return jsonb_build_object('id',v_product.id,'sku',v_product.sku,'name',v_product.name,
    'catalog_status',v_product.catalog_status,'approved_by',v_product.approved_by,
    'approved_at',v_product.approved_at,'version',v_product.version);
end;
$$;

create or replace function public.mme_catalog_publish_product(
  p_actor_user_id uuid, p_product_id uuid
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_product public.products%rowtype;
begin
  if not public.mme_employee_authorize_catalog_action(p_actor_user_id,'catalog.publish',p_product_id,null) then
    raise exception 'Catalog publication permission denied' using errcode='42501';
  end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found or v_product.catalog_status <> 'pending_approval'
     or v_product.approved_by is null or v_product.approved_at is null then
    raise exception 'Product must be approved and awaiting publication' using errcode='40001';
  end if;
  update public.products set catalog_status='published', published_at=now()
  where id=p_product_id returning * into v_product;
  insert into public.product_catalog_events(product_id,event_type,actor_id,product_version,event_data)
  values(v_product.id,'published',p_actor_user_id,v_product.version,'{}'::jsonb);
  return jsonb_build_object('id',v_product.id,'sku',v_product.sku,'name',v_product.name,
    'catalog_status',v_product.catalog_status,'approved_by',v_product.approved_by,
    'approved_at',v_product.approved_at,'published_at',v_product.published_at,'version',v_product.version);
end;
$$;

create or replace function public.mme_catalog_revise_returned_product(
  p_actor_user_id uuid, p_product_id uuid, p_expected_version integer, p_product_data jsonb
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_product public.products%rowtype;
  v_category_id uuid;
  v_snapshot jsonb;
  v_name text;
  v_sku text;
  v_slug text;
begin
  if p_product_data is null or jsonb_typeof(p_product_data) <> 'object'
     or p_expected_version is null or p_expected_version < 1 then
    raise exception 'Invalid revision payload' using errcode='22023';
  end if;
  if not public.mme_employee_authorize_catalog_action(p_actor_user_id,'catalog.edit',p_product_id,null) then
    raise exception 'Catalog edit permission denied' using errcode='42501';
  end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found or v_product.catalog_status <> 'changes_requested'
     or v_product.created_by is distinct from p_actor_user_id then
    raise exception 'Only the original creator may revise a returned draft' using errcode='42501';
  end if;
  if v_product.version <> p_expected_version then
    raise exception 'Product version conflict' using errcode='40001';
  end if;

  v_name := nullif(btrim(p_product_data->>'name'),'');
  v_sku := nullif(btrim(p_product_data->>'sku'),'');
  if v_name is null or length(v_name)>160 or v_sku is null
     or v_sku !~ '^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$' then
    raise exception 'Invalid product name or SKU' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_product_data->'specifications','{}'::jsonb)) <> 'object'
     or octet_length(coalesce(p_product_data->'specifications','{}'::jsonb)::text)>12000 then
    raise exception 'Invalid specifications object' using errcode='22023';
  end if;
  select id into v_category_id from public.product_categories
   where slug=p_product_data->>'category' and is_active=true;
  if v_category_id is null then raise exception 'Product category is unavailable' using errcode='22023'; end if;

  v_snapshot := jsonb_build_object(
    'category_id',v_product.category_id,'sku',v_product.sku,'slug',v_product.slug,'name',v_product.name,
    'brand',v_product.brand,'model_number',v_product.model_number,'upc_ean',v_product.upc_ean,
    'description',v_product.description,'condition',v_product.condition,'tracking_mode',v_product.tracking_mode,
    'specifications',v_product.specifications,'warranty_summary',v_product.warranty_summary,
    'catalog_status',v_product.catalog_status,'version',v_product.version
  );

  update public.products set
    category_id=v_category_id, sku=v_sku,
    slug=left(regexp_replace(lower(v_name),'[^a-z0-9]+','-','g'),100)||'-'||lower(v_sku),
    name=v_name,
    brand=nullif(btrim(p_product_data->>'brand'),''),
    model_number=nullif(btrim(p_product_data->>'model_number'),''),
    upc_ean=nullif(btrim(p_product_data->>'upc_ean'),''),
    description=nullif(btrim(p_product_data->>'description'),''),
    condition=p_product_data->>'condition',
    tracking_mode=p_product_data->>'tracking_mode',
    specifications=coalesce(p_product_data->'specifications','{}'::jsonb),
    warranty_summary=nullif(btrim(p_product_data->>'warranty_summary'),''),
    catalog_status='draft', correction_notes=null, returned_by=null, returned_at=null,
    approved_by=null, approved_at=null, published_at=null
  where id=p_product_id returning * into v_product;

  insert into public.product_catalog_revisions(product_id,product_version,actor_id,revision_reason,snapshot)
  values(v_product.id,p_expected_version,p_actor_user_id,'Employee correction after reviewer return',v_snapshot);
  insert into public.product_catalog_events(product_id,event_type,actor_id,product_version,event_data)
  values(v_product.id,'employee_revised',p_actor_user_id,v_product.version,
    jsonb_build_object('prior_version',p_expected_version));
  return jsonb_build_object('id',v_product.id,'sku',v_product.sku,'name',v_product.name,
    'catalog_status',v_product.catalog_status,'version',v_product.version,'updated_at',v_product.updated_at);
end;
$$;

revoke all on function public.mme_catalog_return_for_correction(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.mme_catalog_approve_product(uuid,uuid) from public, anon, authenticated;
revoke all on function public.mme_catalog_publish_product(uuid,uuid) from public, anon, authenticated;
revoke all on function public.mme_catalog_revise_returned_product(uuid,uuid,integer,jsonb) from public, anon, authenticated;
grant execute on function public.mme_catalog_return_for_correction(uuid,uuid,text) to service_role;
grant execute on function public.mme_catalog_approve_product(uuid,uuid) to service_role;
grant execute on function public.mme_catalog_publish_product(uuid,uuid) to service_role;
grant execute on function public.mme_catalog_revise_returned_product(uuid,uuid,integer,jsonb) to service_role;

comment on function public.mme_catalog_return_for_correction(uuid,uuid,text) is 'Atomic reviewer return plus immutable catalog event; actor ID must be server-derived.';
comment on function public.mme_catalog_approve_product(uuid,uuid) is 'Atomic product approval plus immutable catalog event; actor ID must be server-derived.';
comment on function public.mme_catalog_publish_product(uuid,uuid) is 'Atomic product publication plus immutable catalog event; actor ID must be server-derived.';
comment on function public.mme_catalog_revise_returned_product(uuid,uuid,integer,jsonb) is 'Atomic creator-only product revision, immutable prior snapshot, and catalog event; actor ID must be server-derived.';

commit;
