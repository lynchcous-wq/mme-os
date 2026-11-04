-- Build 006: safely materialize and claim workflow steps.
-- Step handlers execute only through allowlisted MME OS module APIs, never dynamic SQL.
begin;

alter table public.mme_workflow_step_runs
  add column idempotency_key text,
  add column locked_at timestamptz,
  add column locked_by text,
  add column lease_expires_at timestamptz,
  add column max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  add column available_at timestamptz not null default now(),
  add constraint mme_workflow_step_run_lock_pair_check
    check ((locked_at is null)=(locked_by is null));

create unique index mme_workflow_step_idempotency_idx
  on public.mme_workflow_step_runs(idempotency_key)
  where idempotency_key is not null;

create index mme_workflow_step_claim_idx
  on public.mme_workflow_step_runs(execution_id,step_order,available_at)
  where step_status in ('pending','retrying','running');

create function public.mme_initialize_workflow_steps(
  p_execution_id uuid,
  p_worker_identity text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_execution public.mme_workflow_executions%rowtype;
  v_definition public.mme_workflow_definitions%rowtype;
  v_steps jsonb;
  v_step jsonb;
  v_key text;
  v_type text;
  v_count integer:=0;
  v_index integer:=0;
begin
  if p_execution_id is null or p_worker_identity is null
     or length(btrim(p_worker_identity)) not between 2 and 100 then
    raise exception 'Invalid workflow step initialization request' using errcode='22023';
  end if;

  select * into v_execution
    from public.mme_workflow_executions
   where id=p_execution_id for update;
  if not found or v_execution.execution_status<>'running'
     or v_execution.locked_by<>btrim(p_worker_identity)
     or v_execution.lease_expires_at<=now() then
    raise exception 'Execution lease is not owned by this worker' using errcode='42501';
  end if;

  select * into v_definition
    from public.mme_workflow_definitions
   where id=v_execution.workflow_definition_id;
  if not found or v_definition.status<>'active'
     or v_definition.version<>v_execution.workflow_version
     or v_definition.workflow_key<>v_execution.workflow_key then
    raise exception 'Workflow definition is no longer active or does not match execution snapshot' using errcode='55000';
  end if;

  v_steps:=v_definition.definition->'steps';
  if v_steps is null or jsonb_typeof(v_steps)<>'array'
     or jsonb_array_length(v_steps)<1 or jsonb_array_length(v_steps)>100 then
    raise exception 'Workflow definition must contain between 1 and 100 steps' using errcode='22023';
  end if;

  if exists (
    select 1
      from jsonb_array_elements(v_steps) s
     where jsonb_typeof(s)<>'object'
        or coalesce(s->>'key','') !~ '^[a-z][a-z0-9_.-]{1,95}$'
        or coalesce(s->>'type','') not in
          ('module_command','create_task','request_approval','notify','wait','condition')
        or jsonb_typeof(coalesce(s->'config','{}'::jsonb))<>'object'
  ) then
    raise exception 'Workflow contains an invalid step descriptor' using errcode='22023';
  end if;

  if (select count(distinct s->>'key') from jsonb_array_elements(v_steps) s)
     <> jsonb_array_length(v_steps) then
    raise exception 'Workflow step keys must be unique' using errcode='22023';
  end if;

  if exists (select 1 from public.mme_workflow_step_runs where execution_id=p_execution_id) then
    select count(*) into v_count from public.mme_workflow_step_runs where execution_id=p_execution_id;
    return v_count;
  end if;

  for v_step in select value from jsonb_array_elements(v_steps)
  loop
    v_key:=v_step->>'key';
    v_type:=v_step->>'type';
    insert into public.mme_workflow_step_runs(
      execution_id,step_key,step_order,step_type,input_reference,idempotency_key
    ) values (
      p_execution_id,v_key,v_index,v_type,
      coalesce(v_step->'config','{}'::jsonb),
      'workflow-step:'||p_execution_id::text||':'||v_key
    );
    v_index:=v_index+1;
  end loop;

  insert into public.mme_workflow_execution_events(
    execution_id,event_type,actor_service,event_data
  ) values (
    p_execution_id,'execution.steps_initialized',btrim(p_worker_identity),
    jsonb_build_object('step_count',v_index,'workflow_version',v_execution.workflow_version)
  );

  return v_index;
end;
$$;

create function public.mme_claim_workflow_step(
  p_execution_id uuid,
  p_worker_identity text,
  p_lease_seconds integer default 120
)
returns setof public.mme_workflow_step_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_execution public.mme_workflow_executions%rowtype;
  v_step_id bigint;
begin
  if p_execution_id is null or p_worker_identity is null
     or length(btrim(p_worker_identity)) not between 2 and 100
     or p_lease_seconds is null or p_lease_seconds not between 30 and 900 then
    raise exception 'Invalid workflow step claim request' using errcode='22023';
  end if;

  select * into v_execution
    from public.mme_workflow_executions
   where id=p_execution_id;
  if not found or v_execution.execution_status<>'running'
     or v_execution.locked_by<>btrim(p_worker_identity)
     or v_execution.lease_expires_at<=now() then
    raise exception 'Execution lease is not owned by this worker' using errcode='42501';
  end if;

  select s.id into v_step_id
    from public.mme_workflow_step_runs s
   where s.execution_id=p_execution_id
     and s.available_at<=now()
     and (
       s.step_status in ('pending','retrying')
       or (s.step_status='running' and s.lease_expires_at<=now())
     )
     and not exists (
       select 1 from public.mme_workflow_step_runs prior
        where prior.execution_id=s.execution_id
          and prior.step_order<s.step_order
          and prior.step_status not in ('succeeded','skipped')
     )
   order by s.step_order
   for update skip locked
   limit 1;

  if v_step_id is null then return; end if;

  return query
  update public.mme_workflow_step_runs s
     set step_status='running',
         attempt_count=attempt_count+1,
         locked_at=now(),locked_by=btrim(p_worker_identity),
         lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
         started_at=coalesce(started_at,now())
   where s.id=v_step_id
  returning s.*;
end;
$$;

create function public.mme_complete_workflow_step(
  p_step_run_id bigint,
  p_worker_identity text,
  p_success boolean,
  p_output_reference jsonb default '{}'::jsonb,
  p_error_code text default null,
  p_error_summary text default null,
  p_retry_delay_seconds integer default 60
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_step public.mme_workflow_step_runs%rowtype;
  v_execution public.mme_workflow_executions%rowtype;
  v_status text;
begin
  if p_step_run_id is null or p_worker_identity is null
     or p_success is null or p_output_reference is null
     or jsonb_typeof(p_output_reference)<>'object'
     or p_retry_delay_seconds is null or p_retry_delay_seconds not between 1 and 86400
     or coalesce(length(p_error_summary),0)>1000 then
    raise exception 'Invalid workflow step completion request' using errcode='22023';
  end if;

  select * into v_step from public.mme_workflow_step_runs
   where id=p_step_run_id for update;
  if not found or v_step.step_status<>'running'
     or v_step.locked_by<>btrim(p_worker_identity)
     or v_step.lease_expires_at<=now() then
    raise exception 'Step lease is not owned by this worker' using errcode='42501';
  end if;

  select * into v_execution from public.mme_workflow_executions
   where id=v_step.execution_id;
  if not found or v_execution.execution_status<>'running'
     or v_execution.locked_by<>btrim(p_worker_identity)
     or v_execution.lease_expires_at<=now() then
    raise exception 'Parent execution lease is not owned by this worker' using errcode='42501';
  end if;

  if p_success then
    v_status:='succeeded';
  elsif v_step.attempt_count>=v_step.max_attempts then
    v_status:='failed';
  else
    v_status:='retrying';
  end if;

  update public.mme_workflow_step_runs
     set step_status=v_status,
         output_reference=case when p_success then p_output_reference else output_reference end,
         last_error_code=case when p_success then null else left(p_error_code,120) end,
         last_error_summary=case when p_success then null else p_error_summary end,
         available_at=case when v_status='retrying'
           then now()+make_interval(secs=>p_retry_delay_seconds) else available_at end,
         locked_at=null,locked_by=null,lease_expires_at=null,
         finished_at=case when v_status in ('succeeded','failed') then now() else null end
   where id=p_step_run_id;

  insert into public.mme_workflow_execution_events(
    execution_id,step_run_id,event_type,actor_service,event_data
  ) values (
    v_step.execution_id,p_step_run_id,'step.'||v_status,btrim(p_worker_identity),
    jsonb_build_object('step_key',v_step.step_key,'attempt',v_step.attempt_count,
                       'idempotency_key',v_step.idempotency_key,'error_code',p_error_code)
  );

  if v_status='failed' then
    update public.mme_workflow_executions
       set execution_status='failed',last_error_code='step_failed',
           last_error_summary='Workflow step '||v_step.step_key||' exhausted its retry policy',
           locked_at=null,locked_by=null,lease_expires_at=null
     where id=v_execution.id;
  elsif v_status='succeeded' and not exists (
    select 1 from public.mme_workflow_step_runs
     where execution_id=v_execution.id and step_status not in ('succeeded','skipped')
       and id<>p_step_run_id
  ) then
    update public.mme_workflow_executions
       set execution_status='succeeded',finished_at=now(),
           locked_at=null,locked_by=null,lease_expires_at=null,
           last_error_code=null,last_error_summary=null
     where id=v_execution.id;
    insert into public.mme_workflow_execution_events(
      execution_id,event_type,actor_service,event_data
    ) values(v_execution.id,'execution.succeeded',btrim(p_worker_identity),'{}'::jsonb);
  end if;

  return v_status;
end;
$$;

revoke all on function public.mme_initialize_workflow_steps(uuid,text) from public,anon,authenticated;
revoke all on function public.mme_claim_workflow_step(uuid,text,integer) from public,anon,authenticated;
revoke all on function public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer)
  from public,anon,authenticated;
grant execute on function public.mme_initialize_workflow_steps(uuid,text) to service_role;
grant execute on function public.mme_claim_workflow_step(uuid,text,integer) to service_role;
grant execute on function public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer)
  to service_role;

comment on function public.mme_initialize_workflow_steps(uuid,text) is
  'Materializes validated JSON step descriptors once for a leased execution; it never evaluates SQL or arbitrary code.';
comment on function public.mme_claim_workflow_step(uuid,text,integer) is
  'Claims the next sequential step with SKIP LOCKED and a bounded lease; returns its deterministic idempotency key.';
comment on function public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer) is
  'Records step outcome, bounded retry, audit event, and execution completion; external side effects must use the returned stable idempotency key with allowlisted module APIs.';

commit;
