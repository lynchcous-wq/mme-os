begin;

create or replace function public.mme_catalog_submit_product(
  p_actor_user_id uuid, p_product_id uuid
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare v_product public.products%rowtype;
begin
  if not public.mme_employee_authorize_catalog_action(p_actor_user_id,'catalog.submit',p_product_id,null) then
    raise exception 'Catalog submission permission denied' using errcode='42501';
  end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found or v_product.created_by is distinct from p_actor_user_id
     or v_product.catalog_status <> 'draft' then
    raise exception 'Only the creator may submit a draft product' using errcode='42501';
  end if;
  update public.products set catalog_status='pending_approval'
   where id=p_product_id returning * into v_product;
  insert into public.product_catalog_events(product_id,event_type,actor_id,product_version,event_data)
  values(v_product.id,'submitted_for_approval',p_actor_user_id,v_product.version,'{}'::jsonb);
  return jsonb_build_object('id',v_product.id,'sku',v_product.sku,'name',v_product.name,
    'catalog_status',v_product.catalog_status,'version',v_product.version);
end;
$$;

create or replace function public.mme_catalog_publish_product(
  p_actor_user_id uuid, p_product_id uuid
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_product public.products%rowtype;
  v_ceo_user_id uuid;
  v_approver_is_delegated boolean := false;
begin
  if not public.mme_employee_authorize_catalog_action(p_actor_user_id,'catalog.publish',p_product_id,null) then
    raise exception 'Catalog publication permission denied' using errcode='42501';
  end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found or v_product.catalog_status <> 'pending_approval'
     or v_product.approved_by is null or v_product.approved_at is null then
    raise exception 'Product must be approved and awaiting publication' using errcode='40001';
  end if;

  select ceo_user_id into v_ceo_user_id
    from public.employee_security_settings where singleton=true;
  if v_product.approved_by is distinct from v_ceo_user_id then
    select exists (
      select 1 from public.employee_permission_grants g
      join public.employee_relationships e on e.user_id=g.employee_user_id
      where g.employee_user_id=v_product.approved_by
        and e.employment_status='active'
        and g.permission_key='catalog.approve'
        and g.revoked_at is null
        and (g.expires_at is null or g.expires_at>now())
        and g.scope='{}'::jsonb
    ) into v_approver_is_delegated;
    if not v_approver_is_delegated then
      raise exception 'Product approval was not made by the CEO or an active delegated approver' using errcode='42501';
    end if;
  end if;

  update public.products set catalog_status='published', published_at=now()
   where id=p_product_id returning * into v_product;
  insert into public.product_catalog_events(product_id,event_type,actor_id,product_version,event_data)
  values(v_product.id,'published',p_actor_user_id,v_product.version,
    jsonb_build_object('approved_by',v_product.approved_by));
  return jsonb_build_object('id',v_product.id,'sku',v_product.sku,'name',v_product.name,
    'catalog_status',v_product.catalog_status,'approved_by',v_product.approved_by,
    'approved_at',v_product.approved_at,'published_at',v_product.published_at,'version',v_product.version);
end;
$$;

revoke all on function public.mme_catalog_submit_product(uuid,uuid) from public, anon, authenticated;
grant execute on function public.mme_catalog_submit_product(uuid,uuid) to service_role;
comment on function public.mme_catalog_submit_product(uuid,uuid) is
 'Atomic creator-only draft submission and immutable audit event; actor ID must be server-derived.';

commit;
