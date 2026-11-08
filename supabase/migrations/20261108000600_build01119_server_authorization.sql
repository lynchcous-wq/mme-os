-- Build 011.19 — fail-closed server authorization.
-- Public evaluator is SECURITY INVOKER; the only definer helper checks the
-- caller's own Auth session and has no caller-controlled identifiers.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

-- Move the previously created privileged provisioning routine out of the
-- exposed public schema. It remains service-role-only.
alter function public.mme_prepare_ceo_provisioning(text, text) set schema private;
revoke all on function private.mme_prepare_ceo_provisioning(text, text) from public, anon, authenticated;
grant execute on function private.mme_prepare_ceo_provisioning(text, text) to service_role;

create or replace function private.mme_session_is_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid;
  v_session_id uuid;
  v_session_text text;
begin
  v_uid := auth.uid();
  v_session_text := auth.jwt()->>'session_id';
  if v_uid is null or v_session_text is null or v_session_text = '' then
    return false;
  end if;
  begin
    v_session_id := v_session_text::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  return exists (
    select 1
    from auth.sessions s
    where s.id = v_session_id
      and s.user_id = v_uid
      and (s.not_after is null or s.not_after > now())
  );
end;
$function$;
revoke all on function private.mme_session_is_active() from public, anon;
grant execute on function private.mme_session_is_active() to authenticated, service_role;

-- Templates are visible to a signed-in employee only when they are attached
-- to that employee's own active CEO role assignment.
grant select on public.mme_role_permission_templates to authenticated;
drop policy if exists mme_role_permission_templates_own_approved_read
  on public.mme_role_permission_templates;
create policy mme_role_permission_templates_own_approved_read
on public.mme_role_permission_templates
for select to authenticated
using (
  approval_status = 'approved'
  and exists (
    select 1
    from public.mme_roles r
    join public.mme_role_assignments ra on ra.role_id = r.id
    join public.mme_employee_relationships er on er.id = ra.employee_relationship_id
    join public.mme_person_identities pi on pi.id = er.person_identity_id
    where r.role_key = mme_role_permission_templates.role_key
      and r.active = true
      and ra.status = 'active'
      and ra.effective_from <= now()
      and (ra.effective_until is null or ra.effective_until > now())
      and er.status = 'active'
      and pi.auth_user_id = (select auth.uid())
      and pi.security_status = 'active'
  )
);

create or replace function public.mme_authorize(
  p_resource_key text,
  p_action_key text,
  p_target_identity_id uuid default null
)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_uid uuid;
  v_claims jsonb;
  v_iat bigint;
  v_aal text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    return false;
  end if;

  v_claims := auth.jwt();
  v_aal := coalesce(v_claims->>'aal', 'aal1');
  if not private.mme_session_is_active() then
    return false;
  end if;

  if v_claims->>'iat' !~ '^[0-9]+$' then
    return false;
  end if;
  v_iat := (v_claims->>'iat')::bigint;

  return exists (
    select 1
    from public.mme_role_permission_templates t
    join public.mme_roles r
      on r.role_key = t.role_key and r.active = true
    join public.mme_role_assignments ra
      on ra.role_id = r.id
     and ra.status = 'active'
     and ra.effective_from <= now()
     and (ra.effective_until is null or ra.effective_until > now())
    join public.mme_employee_relationships er
      on er.id = ra.employee_relationship_id and er.status = 'active'
    join public.mme_person_identities pi
      on pi.id = er.person_identity_id
     and pi.auth_user_id = v_uid
     and pi.security_status = 'active'
    join public.mme_permission_grants g
      on g.role_assignment_id = ra.id
     and g.resource_key = t.resource_key
     and g.action_key = t.action_key
     and g.status = 'active'
    where t.resource_key = p_resource_key
      and t.action_key = p_action_key
      and t.approval_status = 'approved'
      and (not t.requires_mfa or v_aal = 'aal2')
      and (not t.requires_recent_auth
           or (to_timestamp(v_iat) >= now() - interval '10 minutes'
               and to_timestamp(v_iat) <= now() + interval '60 seconds'))
      and ra.scope @> (t.scope - 'self_target_allowed' - 'requires_secondary_approval')
      and g.scope @> (t.scope - 'self_target_allowed' - 'requires_secondary_approval')
      and not (
        t.scope->>'self_target_allowed' = 'false'
        and p_target_identity_id = pi.id
      )
      -- No unlock action can pass until a separate two-person approval
      -- workflow exists and is wired into the evaluator.
      and not (t.scope->>'requires_secondary_approval' = 'true')
  );
end;
$function$;

revoke all on function public.mme_authorize(text, text, uuid) from public, anon;
grant execute on function public.mme_authorize(text, text, uuid) to authenticated, service_role;
