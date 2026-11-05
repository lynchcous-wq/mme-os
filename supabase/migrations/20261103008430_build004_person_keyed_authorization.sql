-- Build 004: person-keyed catalog and inventory authorization.
-- Additive parallel decision points. Legacy Auth-UUID functions remain intact.
-- Until reviewed person links, CEO person provisioning, and grants are populated,
-- these functions fail closed; they do not fall back to Auth-UUID authorization.
begin;

create function public.mme_person_authorize_catalog_action(
  p_actor_person_id uuid,
  p_permission_key text,
  p_target_product_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_ceo_person_id uuid;
  v_frozen boolean;
  v_employment_status text;
  v_creator_person_id uuid;
  v_catalog_status text;
  v_approved_by uuid;
  v_approved_at timestamptz;
begin
  if p_actor_person_id is null
     or p_permission_key is null
     or p_permission_key !~ '^catalog\.[a-z][a-z0-9_.:-]{0,80}$' then
    return false;
  end if;

  select ceo_person_id, employee_access_frozen
    into v_ceo_person_id, v_frozen
    from public.employee_security_settings
   where singleton = true;

  if not found or v_frozen is distinct from false or v_ceo_person_id is null then
    return false;
  end if;

  select employment_status
    into v_employment_status
    from public.employee_relationships
   where person_id = p_actor_person_id;

  if v_employment_status is distinct from 'active' then
    return false;
  end if;

  if p_permission_key in ('catalog.approve', 'catalog.publish') then
    if p_target_product_id is null then
      return false;
    end if;

    select public.mme_resolve_person_for_auth_subject(created_by),
           catalog_status, approved_by, approved_at
      into v_creator_person_id, v_catalog_status, v_approved_by, v_approved_at
      from public.products
     where id = p_target_product_id;

    if not found or v_creator_person_id is null
       or p_actor_person_id = v_creator_person_id then
      return false;
    end if;

    if p_permission_key = 'catalog.approve'
       and v_catalog_status <> 'pending_approval' then
      return false;
    end if;

    if p_permission_key = 'catalog.publish'
       and (v_catalog_status <> 'pending_approval'
            or v_approved_by is null
            or v_approved_at is null) then
      return false;
    end if;
  end if;

  if p_actor_person_id = v_ceo_person_id then
    return true;
  end if;

  return exists (
    select 1
      from public.employee_permission_grants g
     where g.person_id = p_actor_person_id
       and g.permission_key = p_permission_key
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
       and (
         g.scope = '{}'::jsonb
         or (
           p_target_product_id is not null
           and g.scope ->> 'product_id' = p_target_product_id::text
         )
       )
  );
end;
$$;

create function public.mme_person_authorize_inventory_action(
  p_actor_person_id uuid,
  p_permission_key text,
  p_target_product_id uuid default null,
  p_target_location_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_ceo_person_id uuid;
  v_frozen boolean;
  v_employment_status text;
begin
  if p_actor_person_id is null
     or p_permission_key is null
     or p_permission_key !~ '^inventory\.inspection\.(view|submit|resolve|approve)$' then
    return false;
  end if;

  select ceo_person_id, employee_access_frozen
    into v_ceo_person_id, v_frozen
    from public.employee_security_settings
   where singleton = true;

  if not found or v_frozen is distinct from false or v_ceo_person_id is null then
    return false;
  end if;

  select employment_status
    into v_employment_status
    from public.employee_relationships
   where person_id = p_actor_person_id;

  if v_employment_status is distinct from 'active' then
    return false;
  end if;

  if p_actor_person_id = v_ceo_person_id then
    return true;
  end if;

  return exists (
    select 1
      from public.employee_permission_grants g
     where g.person_id = p_actor_person_id
       and g.permission_key = p_permission_key
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
       and (
         g.scope = '{}'::jsonb
         or (
           p_target_product_id is not null
           and g.scope ->> 'product_id' = p_target_product_id::text
         )
         or (
           p_target_location_id is not null
           and g.scope ->> 'location_id' = p_target_location_id::text
         )
       )
  );
end;
$$;

revoke all on function public.mme_person_authorize_catalog_action(uuid,text,uuid)
  from public, anon, authenticated;
revoke all on function public.mme_person_authorize_inventory_action(uuid,text,uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.mme_person_authorize_catalog_action(uuid,text,uuid)
  to service_role;
grant execute on function public.mme_person_authorize_inventory_action(uuid,text,uuid,uuid)
  to service_role;

comment on function public.mme_person_authorize_catalog_action(uuid,text,uuid) is
  'Build 004 person-keyed catalog authorization. No Auth-UUID fallback; requires active employee person link, configured CEO person, and person-keyed grants.';
comment on function public.mme_person_authorize_inventory_action(uuid,text,uuid,uuid) is
  'Build 004 person-keyed inventory inspection authorization. No Auth-UUID fallback; requires active employee person link, configured CEO person, and person-keyed grants.';

commit;
