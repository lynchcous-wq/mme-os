begin;

-- Build 004: preserve legacy global freeze and explicitly provisioned CEO
-- authority for the legacy permission families only.
create or replace function public.mme_authorize_employee_action(
  p_actor_auth_user_id uuid,
  p_resource_key text,
  p_action_key text,
  p_requested_scope jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_ceo_user_id uuid;
  v_employee_access_frozen boolean;
begin
  if p_actor_auth_user_id is null
     or p_resource_key is null
     or p_resource_key !~ '^[a-z][a-z0-9_.:-]{0,99}$'
     or p_action_key is null
     or p_action_key !~ '^[a-z][a-z0-9_.:-]{0,99}$'
     or p_requested_scope is null
     or jsonb_typeof(p_requested_scope) <> 'object' then
    return false;
  end if;

  select s.ceo_user_id, s.employee_access_frozen
    into v_ceo_user_id, v_employee_access_frozen
    from public.employee_security_settings s
   where s.singleton is true;

  -- Preserve the legacy global deny: missing CEO provisioning or an active
  -- employee freeze blocks every Build 004 employee authorization decision.
  if not found
     or v_ceo_user_id is null
     or v_employee_access_frozen is distinct from false then
    return false;
  end if;

  -- Legacy CEO bypass is intentionally limited to permission families that
  -- already had this behavior. New Build 004 resources still require grants.
  if p_actor_auth_user_id = v_ceo_user_id
     and (
       (p_resource_key = 'inventory.inspection'
         and p_action_key in ('view','submit','resolve','approve'))
       or (p_resource_key = 'catalog'
         and p_action_key in ('approve','publish'))
       or (p_resource_key = 'tasks'
         and p_action_key ~ '^[a-z][a-z0-9_.:-]{0,80}$')
     ) then
    return exists (
      select 1
      from public.mme_person_identities p
      join public.mme_employee_relationships e
        on e.person_identity_id = p.id
      join public.employee_relationships legacy_e
        on legacy_e.user_id = p.auth_user_id
      where p.auth_user_id = p_actor_auth_user_id
        and p.security_status = 'active'
        and e.status = 'active'
        and legacy_e.employment_status = 'active'
    );
  end if;

  return exists (
    select 1
      from public.mme_person_identities p
      join public.mme_employee_relationships e on e.person_identity_id = p.id
      join public.mme_role_assignments ra on ra.employee_relationship_id = e.id
      join public.mme_roles r on r.id = ra.role_id
      join public.mme_permission_grants g on g.role_assignment_id = ra.id
     where p.auth_user_id = p_actor_auth_user_id
       and p.security_status = 'active'
       and e.status = 'active'
       and r.active is true
       and ra.status = 'active'
       and ra.effective_from <= statement_timestamp()
       and (ra.effective_until is null or ra.effective_until > statement_timestamp())
       and (ra.scope = '{}'::jsonb or ra.scope @> p_requested_scope)
       and g.status = 'active'
       and g.resource_key = p_resource_key
       and g.action_key = p_action_key
       and (g.scope = '{}'::jsonb or g.scope @> p_requested_scope)
  );
end;
$$;

comment on function public.mme_authorize_employee_action(uuid, text, text, jsonb) is
  'Server-only deny-by-default employee authorization. Requires provisioned legacy CEO control and global employee freeze off. Preserves CEO bypass only for legacy inventory inspection, catalog, and task permission families, requiring active legacy and Build 004 employee relationships plus active unlocked person identity. All other actions require active scoped Build 004 role grants. Actor UUID must come from a validated server session.';

commit;
