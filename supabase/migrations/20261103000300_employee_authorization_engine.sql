begin;

-- This function is an authorization decision point for trusted server code.
-- The caller must derive p_actor_user_id from a validated identity-provider session.
-- It is not callable by browser roles; only the server's service_role may execute it.
create function public.mme_employee_authorize_catalog_action(
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

  -- No actor, including the CEO, may approve or publish their own submission.
  if p_permission_key in ('catalog.approve', 'catalog.publish')
     and p_submitter_user_id is not null
     and p_actor_user_id = p_submitter_user_id then
    return false;
  end if;

  -- CEO authority is explicit in the provisioned security settings.
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
  'Server-only catalog authorization decision. Actor UUID must come from a validated server session; service_role execute only.';

commit;
