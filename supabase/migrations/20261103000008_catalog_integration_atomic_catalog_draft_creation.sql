begin;

create or replace function public.mme_catalog_create_product_draft(
  p_actor_user_id uuid, p_product_data jsonb
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_category_id uuid;
  v_product public.products%rowtype;
  v_name text;
  v_sku text;
  v_category text;
  v_media_url text;
  v_media_type text;
  v_slug text;
begin
  if p_product_data is null or jsonb_typeof(p_product_data)<>'object' then
    raise exception 'Invalid product payload' using errcode='22023';
  end if;
  if not public.mme_employee_authorize_catalog_action(p_actor_user_id,'catalog.create',null,null) then
    raise exception 'Catalog create permission denied' using errcode='42501';
  end if;
  v_name:=nullif(btrim(p_product_data->>'name'),'');
  v_sku:=nullif(btrim(p_product_data->>'sku'),'');
  v_category:=p_product_data->>'category';
  if v_name is null or length(v_name)>160 or v_sku is null
     or v_sku !~ '^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$' then
    raise exception 'Invalid product name or SKU' using errcode='22023';
  end if;
  if p_product_data->>'condition' not in ('new','open_box','like_new','refurbished','used_excellent','used_good','used_fair','parts_only','damaged','inspection_required')
     or p_product_data->>'tracking_mode' not in ('quantity','serialized') then
    raise exception 'Invalid product condition or tracking mode' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_product_data->'specifications','{}'::jsonb))<>'object'
     or octet_length(coalesce(p_product_data->'specifications','{}'::jsonb)::text)>12000 then
    raise exception 'Invalid specifications object' using errcode='22023';
  end if;
  select id into v_category_id from public.product_categories where slug=v_category and is_active=true;
  if v_category_id is null then raise exception 'Product category is unavailable' using errcode='22023'; end if;

  v_media_url:=nullif(btrim(p_product_data->>'media_url'),'');
  if v_media_url is not null and (length(v_media_url)>2048 or v_media_url !~* '^https://') then
    raise exception 'Media URL must be HTTPS and at most 2,048 characters' using errcode='22023';
  end if;

  v_slug:=left(regexp_replace(lower(v_name),'[^a-z0-9]+','-','g'),80)||'-'||
    left(regexp_replace(lower(v_sku),'[^a-z0-9]+','-','g'),64);
  insert into public.products(
    category_id,sku,slug,name,brand,model_number,upc_ean,description,condition,
    tracking_mode,catalog_status,specifications,warranty_summary,created_by
  ) values (
    v_category_id,v_sku,v_slug,v_name,
    nullif(btrim(p_product_data->>'brand'),''),
    nullif(btrim(p_product_data->>'model_number'),''),
    nullif(btrim(p_product_data->>'upc_ean'),''),
    nullif(btrim(p_product_data->>'description'),''),
    p_product_data->>'condition',p_product_data->>'tracking_mode','draft',
    coalesce(p_product_data->'specifications','{}'::jsonb),
    nullif(btrim(p_product_data->>'warranty_summary'),''),p_actor_user_id
  ) returning * into v_product;

  if v_media_url is not null then
    v_media_type:=case when v_media_url ~* '\.(mp4|webm|mov)(\?.*)?$' then 'video' else 'image' end;
    insert into public.product_media(product_id,media_type,external_url,alt_text,is_primary)
    values(v_product.id,v_media_type,v_media_url,v_name||' product media',true);
  end if;

  insert into public.product_catalog_events(product_id,event_type,actor_id,product_version,event_data)
  values(v_product.id,'draft_created',p_actor_user_id,v_product.version,
    jsonb_build_object('source','employee_catalog_api','media_attached',v_media_url is not null));

  return jsonb_build_object('id',v_product.id,'sku',v_product.sku,'name',v_product.name,
    'catalog_status',v_product.catalog_status,'version',v_product.version,'created_at',v_product.created_at);
end;
$$;

revoke all on function public.mme_catalog_create_product_draft(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.mme_catalog_create_product_draft(uuid,jsonb) to service_role;
comment on function public.mme_catalog_create_product_draft(uuid,jsonb) is
 'Atomic product draft creation, optional external media metadata, and immutable audit event. Actor ID must be server-derived.';

commit;
