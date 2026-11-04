-- Build 006: independent approval and controlled activation of immutable workflow versions.
begin;

create table public.mme_workflow_activation_requests (
  id uuid primary key default gen_random_uuid(),
  workflow_definition_id uuid not null references public.mme_workflow_definitions(id) on delete restrict,
  workflow_key text not null,
  workflow_version integer not null,
  definition_sha256 text not null check (definition_sha256 ~ '^[0-9a-f]{64}$'),
  requested_by_user_id uuid not null references auth.users(id) on delete restrict,
  request_reason text not null check (length(btrim(request_reason)) between 3 and 1000),
  request_status text not null default 'pending'
    check (request_status in ('pending','approved','rejected','cancelled')),
  requested_at timestamptz not null default now(),
  decided_by_user_id uuid references auth.users(id) on delete restrict,
  decided_at timestamptz,
  decision_reason text,
  check (
    (request_status='pending' and decided_by_user_id is null and decided_at is null)
    or
    (request_status<>'pending' and decided_by_user_id is not null and decided_at is not null)
  ),
  check (request_status<>'rejected' or (decision_reason is not null and length(btrim(decision_reason))>=3))
);
create unique index mme_workflow_one_pending_activation_idx
  on public.mme_workflow_activation_requests(workflow_definition_id)
  where request_status='pending';
create index mme_workflow_activation_inbox_idx
  on public.mme_workflow_activation_requests(requested_at desc)
  where request_status='pending';

create table public.mme_workflow_activation_events (
  id bigint generated always as identity primary key,
  activation_request_id uuid not null references public.mme_workflow_activation_requests(id) on delete restrict,
  workflow_definition_id uuid not null references public.mme_workflow_definitions(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check (event_type in ('requested','approved','rejected','cancelled','activated','paused','retired')),
  definition_sha256 text not null check (definition_sha256 ~ '^[0-9a-f]{64}$'),
  reason text,
  created_at timestamptz not null default now()
);
create index mme_workflow_activation_events_idx
  on public.mme_workflow_activation_events(workflow_definition_id,created_at);

alter table public.mme_workflow_activation_requests enable row level security;
alter table public.mme_workflow_activation_requests force row level security;
alter table public.mme_workflow_activation_events enable row level security;
alter table public.mme_workflow_activation_events force row level security;
revoke all on public.mme_workflow_activation_requests,public.mme_workflow_activation_events from public,anon,authenticated;
grant all on public.mme_workflow_activation_requests,public.mme_workflow_activation_events to service_role;

create function public.mme_workflow_activation_events_immutable()
returns trigger language plpgsql set search_path=''
as $$ begin raise exception 'Workflow activation history is append-only'; end; $$;
create trigger mme_workflow_activation_events_no_update_delete
before update or delete on public.mme_workflow_activation_events
for each row execute function public.mme_workflow_activation_events_immutable();

create function public.mme_guard_workflow_definition_update()
returns trigger language plpgsql set search_path=''
as $$
begin
  if old.status in ('active','retired') and (
    new.workflow_key is distinct from old.workflow_key
    or new.version is distinct from old.version
    or new.display_name is distinct from old.display_name
    or new.owner_department is distinct from old.owner_department
    or new.trigger_event_type is distinct from old.trigger_event_type
    or new.definition is distinct from old.definition
    or new.definition_sha256 is distinct from old.definition_sha256
    or new.created_by_user_id is distinct from old.created_by_user_id
  ) then
    raise exception 'Activated or retired workflow definitions are immutable';
  end if;
  return new;
end;
$$;
create trigger mme_workflow_definition_immutable_after_activation
before update on public.mme_workflow_definitions
for each row execute function public.mme_guard_workflow_definition_update();

create function public.mme_request_workflow_activation(
  p_actor_user_id uuid,p_workflow_definition_id uuid,p_reason text
)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_definition public.mme_workflow_definitions%rowtype; v_request_id uuid;
begin
  if p_actor_user_id is null or p_workflow_definition_id is null
     or p_reason is null or length(btrim(p_reason)) not between 3 and 1000 then
    raise exception 'Invalid workflow activation request' using errcode='22023';
  end if;
  select * into v_definition from public.mme_workflow_definitions
   where id=p_workflow_definition_id for update;
  if not found then raise exception 'Workflow definition not found' using errcode='P0002'; end if;
  if v_definition.status not in ('draft','paused') then
    raise exception 'Only draft or paused workflows can be submitted for activation' using errcode='55000';
  end if;
  if not public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.workflow.activate',v_definition.owner_department,null
  ) then raise exception 'Not authorized to request workflow activation' using errcode='42501'; end if;

  insert into public.mme_workflow_activation_requests(
    workflow_definition_id,workflow_key,workflow_version,definition_sha256,
    requested_by_user_id,request_reason
  ) values (
    v_definition.id,v_definition.workflow_key,v_definition.version,v_definition.definition_sha256,
    p_actor_user_id,btrim(p_reason)
  ) returning id into v_request_id;

  insert into public.mme_workflow_activation_events(
    activation_request_id,workflow_definition_id,actor_user_id,event_type,definition_sha256,reason
  ) values(v_request_id,v_definition.id,p_actor_user_id,'requested',v_definition.definition_sha256,btrim(p_reason));
  return v_request_id;
end;
$$;

create function public.mme_decide_workflow_activation(
  p_actor_user_id uuid,p_activation_request_id uuid,p_approve boolean,p_reason text default null
)
returns boolean
language plpgsql security definer set search_path=''
as $$
declare v_request public.mme_workflow_activation_requests%rowtype;
        v_definition public.mme_workflow_definitions%rowtype;
        v_event text;
begin
  if p_actor_user_id is null or p_activation_request_id is null or p_approve is null then
    raise exception 'Invalid workflow activation decision' using errcode='22023';
  end if;
  select * into v_request from public.mme_workflow_activation_requests
   where id=p_activation_request_id for update;
  if not found or v_request.request_status<>'pending' then
    raise exception 'Activation request is not pending' using errcode='55000';
  end if;
  if p_actor_user_id=v_request.requested_by_user_id then
    raise exception 'Requester cannot approve their own workflow activation' using errcode='42501';
  end if;
  select * into v_definition from public.mme_workflow_definitions
   where id=v_request.workflow_definition_id for update;
  if not found or v_definition.status not in ('draft','paused')
     or v_definition.definition_sha256<>v_request.definition_sha256 then
    raise exception 'Workflow definition changed or is no longer eligible; submit a new request' using errcode='55000';
  end if;
  if not public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.workflow.activate',v_definition.owner_department,null
  ) then raise exception 'Not authorized to decide workflow activation' using errcode='42501'; end if;
  if not p_approve and (p_reason is null or length(btrim(p_reason))<3) then
    raise exception 'A reason is required for rejection' using errcode='22023';
  end if;

  v_event:=case when p_approve then 'approved' else 'rejected' end;
  update public.mme_workflow_activation_requests
     set request_status=v_event,decided_by_user_id=p_actor_user_id,
         decided_at=now(),decision_reason=case when p_reason is null then null else left(btrim(p_reason),1000) end
   where id=p_activation_request_id;
  insert into public.mme_workflow_activation_events(
    activation_request_id,workflow_definition_id,actor_user_id,event_type,definition_sha256,reason
  ) values(p_activation_request_id,v_definition.id,p_actor_user_id,v_event,
           v_definition.definition_sha256,p_reason);
  return true;
end;
$$;

create function public.mme_activate_approved_workflow(
  p_actor_user_id uuid,p_activation_request_id uuid
)
returns boolean
language plpgsql security definer set search_path=''
as $$
declare v_request public.mme_workflow_activation_requests%rowtype;
        v_definition public.mme_workflow_definitions%rowtype;
begin
  if p_actor_user_id is null or p_activation_request_id is null then
    raise exception 'Invalid workflow activation command' using errcode='22023';
  end if;
  select * into v_request from public.mme_workflow_activation_requests
   where id=p_activation_request_id for update;
  if not found or v_request.request_status<>'approved' then
    raise exception 'Workflow activation has not been approved' using errcode='55000';
  end if;
  select * into v_definition from public.mme_workflow_definitions
   where id=v_request.workflow_definition_id for update;
  if not found or v_definition.status not in ('draft','paused')
     or v_definition.definition_sha256<>v_request.definition_sha256 then
    raise exception 'Workflow definition changed or is not eligible for activation' using errcode='55000';
  end if;
  if not public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.workflow.activate',v_definition.owner_department,null
  ) then raise exception 'Not authorized to activate workflow' using errcode='42501'; end if;

  update public.mme_workflow_definitions
     set status='active',approved_by_user_id=v_request.decided_by_user_id,activated_at=now()
   where id=v_definition.id;
  insert into public.mme_workflow_activation_events(
    activation_request_id,workflow_definition_id,actor_user_id,event_type,definition_sha256,reason
  ) values(p_activation_request_id,v_definition.id,p_actor_user_id,'activated',v_definition.definition_sha256,
           'Activated after independent approval');
  return true;
end;
$$;

create function public.mme_set_workflow_lifecycle(
  p_actor_user_id uuid,p_workflow_definition_id uuid,p_new_status text,p_reason text
)
returns boolean
language plpgsql security definer set search_path=''
as $$
declare v_definition public.mme_workflow_definitions%rowtype;
begin
  if p_actor_user_id is null or p_workflow_definition_id is null
     or p_new_status not in ('paused','retired')
     or p_reason is null or length(btrim(p_reason)) not between 3 and 1000 then
    raise exception 'Invalid workflow lifecycle change' using errcode='22023';
  end if;
  select * into v_definition from public.mme_workflow_definitions
   where id=p_workflow_definition_id for update;
  if not found then raise exception 'Workflow definition not found' using errcode='P0002'; end if;
  if v_definition.status not in ('active','paused') then
    raise exception 'Workflow is not eligible for this lifecycle change' using errcode='55000';
  end if;
  if not public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.workflow.activate',v_definition.owner_department,null
  ) then raise exception 'Not authorized to change workflow lifecycle' using errcode='42501'; end if;

  update public.mme_workflow_definitions
     set status=p_new_status
   where id=p_workflow_definition_id;
  insert into public.mme_workflow_activation_events(
    activation_request_id,workflow_definition_id,actor_user_id,event_type,definition_sha256,reason
  ) values(null,v_definition.id,p_actor_user_id,p_new_status,v_definition.definition_sha256,btrim(p_reason));
  return true;
end;
$$;

revoke all on function public.mme_workflow_activation_events_immutable() from public,anon,authenticated;
revoke all on function public.mme_guard_workflow_definition_update() from public,anon,authenticated;
revoke all on function public.mme_request_workflow_activation(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_decide_workflow_activation(uuid,uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.mme_activate_approved_workflow(uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_set_workflow_lifecycle(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_request_workflow_activation(uuid,uuid,text) to service_role;
grant execute on function public.mme_decide_workflow_activation(uuid,uuid,boolean,text) to service_role;
grant execute on function public.mme_activate_approved_workflow(uuid,uuid) to service_role;
grant execute on function public.mme_set_workflow_lifecycle(uuid,uuid,text,text) to service_role;

comment on table public.mme_workflow_activation_requests is
  'Independent approval requests tied to an exact workflow definition digest; requester cannot approve own activation.';
comment on table public.mme_workflow_activation_events is
  'Append-only workflow activation, pause and retirement audit trail.';
commit;
