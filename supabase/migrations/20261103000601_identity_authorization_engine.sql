begin;

-- Build 004: centralized employee authorization decision point.
-- Actor UUID must come from a validated server-side identity-provider session.
-- This function does not validate or revoke bearer tokens.

alter table public.mme_role_assignments
  add constraint mme_role_assignments_effective_window_check
  check (effective_until is null or effective_until > effective_from),
  add constraint mme_role_assignments_scope_object_check
  check (jsonb_typeof(scope) = 'object');

alter table public.mme_permission_grants
  add constraint mme_permission_grants_scope_object_check
  check (jsonb_typeof(scope) = 'object');

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
       and ra.scope @> p_requested_scope
       and g.status = 'active'
       and g.resource_key = p_resource_key
       and g.action_key = p_action_key
       and g.scope @> p_requested_scope
  );
end;
$$;

revoke all on function public.mme_authorize_employee_action(uuid, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.mme_authorize_employee_action(uuid, text, text, jsonb)
  to service_role;

comment on function public.mme_authorize_employee_action(uuid, text, text, jsonb) is
  'Server-only deny-by-default employee authorization decision. Actor UUID must come from a validated server session. Checks person security lock, active employee relationship, active role, effective role assignment, and matching active scoped permission grant. Does not validate/revoke sessions or replace authorization at every data boundary.';

commit;
