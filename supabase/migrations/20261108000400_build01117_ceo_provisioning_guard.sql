-- Build 011.17 — guarded CEO provisioning.
-- Creates only pending employee/role records for a verified Supabase Auth account.
-- No permission grants are created; activation is a separate reviewed step.
create or replace function public.mme_prepare_ceo_provisioning(
  p_email text,
  p_employee_number text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_identity_id uuid;
  v_employee_id uuid;
  v_assignment_id uuid;
  v_role_id uuid;
  v_email text;
begin
  v_email := lower(btrim(coalesce(p_email, '')));
  if v_email = '' or position('@' in v_email) < 2 then
    raise exception 'A valid email address is required' using errcode = '22023';
  end if;
  if btrim(coalesce(p_employee_number, '')) = '' then
    raise exception 'An employee number is required' using errcode = '22023';
  end if;

  select u.id into v_user_id
  from auth.users u
  where lower(u.email) = v_email
    and u.email_confirmed_at is not null;

  if v_user_id is null then
    raise exception 'No email-confirmed Supabase Auth user exists for this address'
      using errcode = 'P0002';
  end if;

  select pi.id into v_identity_id
  from public.mme_person_identities pi
  where pi.auth_user_id = v_user_id
    and pi.security_status = 'active';

  if v_identity_id is null then
    raise exception 'Active MME person identity was not created for this Auth user'
      using errcode = 'P0002';
  end if;

  select r.id into v_role_id
  from public.mme_roles r
  where r.role_key = 'ceo' and r.active = true;

  if v_role_id is null then
    raise exception 'Active CEO role definition is missing'
      using errcode = 'P0002';
  end if;

  select er.id into v_employee_id
  from public.mme_employee_relationships er
  where er.person_identity_id = v_identity_id;

  if v_employee_id is null then
    insert into public.mme_employee_relationships
      (person_identity_id, employee_number, department_key, position_title, status)
    values
      (v_identity_id, btrim(p_employee_number), 'executive', 'Chief Executive Officer', 'pending')
    returning id into v_employee_id;
  else
    if not exists (
      select 1 from public.mme_employee_relationships er
      where er.id = v_employee_id and er.employee_number = btrim(p_employee_number)
    ) then
      raise exception 'An employee relationship already exists with a different employee number'
        using errcode = '23505';
    end if;
  end if;

  select ra.id into v_assignment_id
  from public.mme_role_assignments ra
  where ra.employee_relationship_id = v_employee_id
    and ra.role_id = v_role_id
    and ra.status in ('pending', 'active');

  if v_assignment_id is null then
    insert into public.mme_role_assignments
      (employee_relationship_id, role_id, scope, status)
    values
      (v_employee_id, v_role_id, jsonb_build_object('organization', 'MME'), 'pending')
    returning id into v_assignment_id;
  end if;

  insert into public.mme_identity_audit_events
    (actor_identity_id, actor_service_key, target_identity_id, action_key, outcome, reason, after_state)
  values
    (null, 'mme_ceo_provisioning', v_identity_id, 'ceo.provisioning_prepared', 'success',
     'Verified Auth user linked to pending CEO employee and role records; no permissions granted',
     jsonb_build_object(
       'email', v_email,
       'employee_relationship_id', v_employee_id,
       'role_assignment_id', v_assignment_id,
       'role_key', 'ceo',
       'employee_status', 'pending',
       'role_assignment_status', 'pending',
       'permission_grants_created', 0
     ));

  return jsonb_build_object(
    'status', 'pending',
    'person_identity_id', v_identity_id,
    'employee_relationship_id', v_employee_id,
    'role_assignment_id', v_assignment_id,
    'role_key', 'ceo',
    'permission_grants_created', 0
  );
end;
$function$;

revoke all on function public.mme_prepare_ceo_provisioning(text, text) from public, anon, authenticated;
grant execute on function public.mme_prepare_ceo_provisioning(text, text) to service_role;
