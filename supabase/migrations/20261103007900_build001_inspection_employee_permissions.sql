-- Build 001: server-only employee authorization for inspection workflows.
-- The server must derive p_actor_user_id from a validated Supabase Auth session.
begin;

create or replace function public.mme_employee_authorize_inventory_action(
  p_actor_user_id uuid,
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
  v_ceo_user_id uuid;
  v_frozen boolean;
  v_employment_status text;
begin
  if p_actor_user_id is null
     or p_permission_key is null
     or p_permission_key !~ '^inventory\.inspection\.(view|submit|resolve|approve)$' then
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

  if p_actor_user_id = v_ceo_user_id then
    return true;
  end if;

  return exists (
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
         or (
           p_target_location_id is not null
           and g.scope ->> 'location_id' = p_target_location_id::text
         )
       )
  );
end;
$$;

revoke all on function public.mme_employee_authorize_inventory_action(uuid,text,uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.mme_employee_authorize_inventory_action(uuid,text,uuid,uuid)
  to service_role;

comment on function public.mme_employee_authorize_inventory_action(uuid,text,uuid,uuid) is
  'Server-only inventory inspection authorization. Actor ID must come from a validated auth session; CEO identity is provisioned out-of-band; frozen or unconfigured access fails closed.';

commit;
