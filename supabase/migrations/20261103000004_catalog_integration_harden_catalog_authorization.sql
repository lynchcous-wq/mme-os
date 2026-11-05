begin;

-- Harden the authorization decision point:
-- Never trust a caller-supplied submitter ID. Resolve the product owner from
-- the protected product row and enforce the catalog state transition.
create or replace function public.mme_employee_authorize_catalog_action(
  p_actor_user_id uuid,
  p_permission_key text,
  p_target_product_id uuid default null,
  p_submitter_user_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_ceo_user_id uuid;
  v_frozen boolean;
  v_employment_status text;
  v_authorized boolean := false;
  v_product_creator uuid;
  v_catalog_status text;
  v_approved_by uuid;
  v_approved_at timestamptz;
begin
  if p_actor_user_id is null
     or p_permission_key is null
     or p_permission_key !~ '^catalog\.[a-z][a-z0-9_.:-]{0,80}$' then
    return false;
  end if;

  select ceo_user_id, employee_access_frozen
    into v_ceo_user_id, v_frozen
    from public.employee_security_settings
   where singleton = true;

  if not found or v_frozen is distinct from false or v_ceo_user_id is null then
    return false;
  end if;

  select employment_status
    into v_employment_status
    from public.employee_relationships
   where user_id = p_actor_user_id;

  if v_employment_status is distinct from 'active' then
    return false;
  end if;

  -- Approval/publication must target a real product and its creator is read
  -- from the database. p_submitter_user_id is retained for call compatibility
  -- but is intentionally never trusted for authorization.
  if p_permission_key in ('catalog.approve', 'catalog.publish') then
    if p_target_product_id is null then
      return false;
    end if;

    select created_by, catalog_status, approved_by, approved_at
      into v_product_creator, v_catalog_status, v_approved_by, v_approved_at
      from public.products
     where id = p_target_product_id;

    if not found or v_product_creator is null
       or p_actor_user_id = v_product_creator then
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

  if p_actor_user_id = v_ceo_user_id then
    return true;
  end if;

  select exists (
    select 1
      from public.employee_permission_grants g
     where g.employee_user_id = p_actor_user_id
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
  ) into v_authorized;

  return coalesce(v_authorized, false);
end;
$$;

revoke all on function public.mme_employee_authorize_catalog_action(uuid, text, uuid, uuid) from public;
revoke all on function public.mme_employee_authorize_catalog_action(uuid, text, uuid, uuid) from anon;
revoke all on function public.mme_employee_authorize_catalog_action(uuid, text, uuid, uuid) from authenticated;
grant execute on function public.mme_employee_authorize_catalog_action(uuid, text, uuid, uuid) to service_role;

comment on function public.mme_employee_authorize_catalog_action(uuid, text, uuid, uuid) is
  'Server-only authorization decision. Actor ID must come from validated server session. Submitter is resolved from product row, not caller input.';

commit;
