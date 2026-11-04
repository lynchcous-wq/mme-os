-- Build 006: reject unknown permission-scope dimensions for workflow actions.
begin;

create or replace function public.mme_employee_authorize_task_action(
  p_actor_user_id uuid,
  p_permission_key text,
  p_department text,
  p_location_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ceo_user_id uuid;
  v_frozen boolean;
  v_employment_status text;
begin
  if p_actor_user_id is null
     or p_permission_key is null
     or p_permission_key !~ '^tasks\.[a-z][a-z0-9_.:-]{0,80}$'
     or p_department is null then
    return false;
  end if;

  select ceo_user_id,employee_access_frozen
    into v_ceo_user_id,v_frozen
    from public.employee_security_settings
   where singleton=true;

  if not found or v_frozen is distinct from false or v_ceo_user_id is null then
    return false;
  end if;

  select employment_status into v_employment_status
    from public.employee_relationships
   where user_id=p_actor_user_id;

  if v_employment_status is distinct from 'active' then
    return false;
  end if;

  if p_actor_user_id=v_ceo_user_id then
    return true;
  end if;

  return exists (
    select 1
      from public.employee_permission_grants g
     where g.employee_user_id=p_actor_user_id
       and g.permission_key=p_permission_key
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at>now())
       and (
         g.scope='{}'::jsonb
         or (
           jsonb_typeof(g.scope)='object'
           and (g.scope - array['department','location_id']::text[])='{}'::jsonb
           and g.scope ? 'department'
           and g.scope->>'department'=p_department
           and (
             not (g.scope ? 'location_id')
             or (p_location_id is not null and g.scope->>'location_id'=p_location_id::text)
           )
         )
         or (
           jsonb_typeof(g.scope)='object'
           and (g.scope - array['department','location_id']::text[])='{}'::jsonb
           and not (g.scope ? 'department')
           and g.scope ? 'location_id'
           and p_location_id is not null
           and g.scope->>'location_id'=p_location_id::text
         )
       )
  );
end;
$$;

comment on function public.mme_employee_authorize_task_action(uuid,text,text,uuid) is
  'Build 006 fail-closed authorization. Only global {}, department, department+location, or location-only scopes are accepted; unknown scope keys never grant access.';

commit;
