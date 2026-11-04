-- Build 006: server-only task creation, assignment and lifecycle transitions.
-- Actor UUIDs must be resolved from a validated Supabase Auth session by trusted server code.
begin;

create function public.mme_employee_authorize_task_action(
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
         or g.scope ->> 'department' = p_department
         or (p_location_id is not null and g.scope ->> 'location_id' = p_location_id::text)
       )
  );
end;
$$;

create function public.mme_create_task(
  p_actor_user_id uuid,
  p_title text,
  p_instructions text,
  p_department text,
  p_location_id uuid default null,
  p_priority text default 'normal',
  p_starts_at timestamptz default null,
  p_due_at timestamptz default null,
  p_estimated_minutes integer default null,
  p_related_record_type text default null,
  p_related_record_id text default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_id uuid;
begin
  if p_title is null or length(btrim(p_title)) not between 3 and 180
     or coalesce(length(p_instructions),0) > 8000
     or p_department is null or p_department !~ '^[a-z][a-z0-9_-]{1,63}$'
     or p_priority not in ('critical','high','normal','low')
     or (p_due_at is not null and p_starts_at is not null and p_due_at < p_starts_at)
     or (p_estimated_minutes is not null and p_estimated_minutes not between 1 and 10080)
     or ((p_related_record_type is null) <> (p_related_record_id is null))
     or (p_related_record_type is not null and p_related_record_type !~ '^[a-z][a-z0-9_.-]{1,63}$')
     or (p_related_record_id is not null and length(p_related_record_id) not between 1 and 180)
     or (p_idempotency_key is not null and length(p_idempotency_key) not between 8 and 180) then
    raise exception 'Task input is invalid' using errcode = '22023';
  end if;

  if not public.mme_employee_authorize_task_action(p_actor_user_id,'tasks.create',p_department,p_location_id) then
    raise exception 'Not authorized to create tasks in this scope' using errcode = '42501';
  end if;

  if p_idempotency_key is not null then
    select id into v_task_id from public.mme_tasks where idempotency_key = p_idempotency_key;
    if found then return v_task_id; end if;
  end if;

  insert into public.mme_tasks(
    title,instructions,department,location_id,priority,starts_at,due_at,
    estimated_minutes,related_record_type,related_record_id,idempotency_key,created_by_user_id
  ) values (
    btrim(p_title),coalesce(p_instructions,''),p_department,p_location_id,p_priority,p_starts_at,p_due_at,
    p_estimated_minutes,p_related_record_type,p_related_record_id,p_idempotency_key,p_actor_user_id
  ) returning id into v_task_id;

  insert into public.mme_task_events(task_id,event_type,actor_user_id,event_data)
  values (v_task_id,'task.created',p_actor_user_id,
    jsonb_build_object('department',p_department,'location_id',p_location_id,'priority',p_priority));

  return v_task_id;
end;
$$;

create function public.mme_assign_task(
  p_actor_user_id uuid,
  p_task_id uuid,
  p_assignee_user_id uuid,
  p_reason text,
  p_assignment_scope jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.mme_tasks%rowtype;
  v_old_assignment_id uuid;
  v_assignment_id uuid;
begin
  if p_task_id is null or p_assignee_user_id is null
     or p_reason is null or length(btrim(p_reason)) not between 3 and 500
     or p_assignment_scope is null or jsonb_typeof(p_assignment_scope) <> 'object' then
    raise exception 'Assignment input is invalid' using errcode = '22023';
  end if;

  select * into v_task from public.mme_tasks where id = p_task_id for update;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;

  if v_task.status in ('completed','rejected','cancelled') then
    raise exception 'Closed tasks cannot be assigned' using errcode = '55000';
  end if;

  if not public.mme_employee_authorize_task_action(p_actor_user_id,'tasks.assign',v_task.department,v_task.location_id) then
    raise exception 'Not authorized to assign tasks in this scope' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.employee_relationships e
     where e.user_id = p_assignee_user_id and e.employment_status = 'active'
  ) then
    raise exception 'Assignee is not an active employee' using errcode = '22023';
  end if;

  select id into v_old_assignment_id
    from public.mme_task_assignments
   where task_id = p_task_id and ended_at is null
   for update;

  if v_old_assignment_id is not null then
    update public.mme_task_assignments
       set ended_at = now(), end_reason = btrim(p_reason)
     where id = v_old_assignment_id;
  end if;

  insert into public.mme_task_assignments(
    task_id,assignee_user_id,assigned_by_user_id,assignment_scope
  ) values (
    p_task_id,p_assignee_user_id,p_actor_user_id,p_assignment_scope
  ) returning id into v_assignment_id;

  update public.mme_tasks
     set status = case when status = 'not_started' then 'assigned' else status end,
         updated_at = now()
   where id = p_task_id;

  insert into public.mme_task_events(task_id,assignment_id,event_type,actor_user_id,reason,event_data)
  values (p_task_id,v_assignment_id,'task.assigned',p_actor_user_id,btrim(p_reason),
    jsonb_build_object('assignee_user_id',p_assignee_user_id,'previous_assignment_id',v_old_assignment_id));

  return v_assignment_id;
end;
$$;

create function public.mme_transition_task(
  p_actor_user_id uuid,
  p_task_id uuid,
  p_new_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.mme_tasks%rowtype;
  v_is_assignee boolean;
  v_can_manage boolean;
  v_allowed boolean := false;
begin
  if p_task_id is null or p_new_status is null then
    raise exception 'Task transition input is invalid' using errcode = '22023';
  end if;

  select * into v_task from public.mme_tasks where id = p_task_id for update;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;

  select exists (
    select 1 from public.mme_task_assignments a
     where a.task_id = p_task_id and a.assignee_user_id = p_actor_user_id and a.ended_at is null
  ) into v_is_assignee;

  v_can_manage := public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.manage',v_task.department,v_task.location_id
  );

  if not v_is_assignee and not v_can_manage then
    raise exception 'Not authorized to transition this task' using errcode = '42501';
  end if;

  v_allowed := case v_task.status
    when 'not_started' then p_new_status in ('assigned','cancelled')
    when 'assigned' then p_new_status in ('accepted','in_progress','pending_information','cancelled')
    when 'accepted' then p_new_status in ('in_progress','pending_information','pending_approval','cancelled')
    when 'in_progress' then p_new_status in ('pending_information','pending_approval','completed','rejected','cancelled')
    when 'pending_information' then p_new_status in ('in_progress','cancelled')
    when 'pending_approval' then p_new_status in ('in_progress','completed','rejected','cancelled')
    else false
  end;

  if not v_allowed then
    raise exception 'Task status transition is not allowed' using errcode = '55000';
  end if;

  if p_new_status in ('rejected','cancelled') and (p_reason is null or length(btrim(p_reason)) < 3) then
    raise exception 'A reason is required for rejection or cancellation' using errcode = '22023';
  end if;

  update public.mme_tasks
     set status = p_new_status,
         completed_at = case when p_new_status = 'completed' then now() else null end,
         cancelled_at = case when p_new_status = 'cancelled' then now() else null end,
         updated_at = now()
   where id = p_task_id;

  insert into public.mme_task_events(task_id,event_type,actor_user_id,reason,event_data)
  values (p_task_id,'task.status_changed',p_actor_user_id,p_reason,
    jsonb_build_object('from_status',v_task.status,'to_status',p_new_status));
end;
$$;

revoke all on function public.mme_employee_authorize_task_action(uuid,text,text,uuid) from public, anon, authenticated;
revoke all on function public.mme_create_task(uuid,text,text,text,uuid,text,timestamptz,timestamptz,integer,text,text,text) from public, anon, authenticated;
revoke all on function public.mme_assign_task(uuid,uuid,uuid,text,jsonb) from public, anon, authenticated;
revoke all on function public.mme_transition_task(uuid,uuid,text,text) from public, anon, authenticated;

grant execute on function public.mme_employee_authorize_task_action(uuid,text,text,uuid) to service_role;
grant execute on function public.mme_create_task(uuid,text,text,text,uuid,text,timestamptz,timestamptz,integer,text,text,text) to service_role;
grant execute on function public.mme_assign_task(uuid,uuid,uuid,text,jsonb) to service_role;
grant execute on function public.mme_transition_task(uuid,uuid,text,text) to service_role;

comment on function public.mme_employee_authorize_task_action(uuid,text,text,uuid) is
  'Build 006 task authorization decision point. Caller must derive actor from validated server session.';
comment on function public.mme_create_task(uuid,text,text,text,uuid,text,timestamptz,timestamptz,integer,text,text,text) is
  'Build 006 server-only task creation with scope authorization, validation, idempotency and immutable event.';
comment on function public.mme_assign_task(uuid,uuid,uuid,text,jsonb) is
  'Build 006 server-only assignment with active employee validation, single-active-assignment locking and history.';
comment on function public.mme_transition_task(uuid,uuid,text,text) is
  'Build 006 server-only validated status transitions; overdue remains derived from due_at and status.';

commit;
