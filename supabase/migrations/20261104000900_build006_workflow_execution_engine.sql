-- Build 006: versioned workflow registry and durable execution queue.
-- Workers invoke authorized MME OS module APIs; this engine never mutates source-module business records.
begin;

create table public.mme_workflow_definitions (
  id uuid primary key default gen_random_uuid(),
  workflow_key text not null check (workflow_key ~ '^[a-z][a-z0-9_.-]{1,95}$'),
  version integer not null check (version > 0),
  display_name text not null check (length(btrim(display_name)) between 3 and 180),
  owner_department text not null check (owner_department ~ '^[a-z][a-z0-9_-]{1,63}$'),
  trigger_event_type text not null check (trigger_event_type ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  definition jsonb not null check (jsonb_typeof(definition)='object'),
  definition_sha256 text not null check (definition_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null default 'draft' check (status in ('draft','active','paused','retired')),
  created_by_user_id uuid not null references auth.users(id) on delete restrict,
  approved_by_user_id uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  unique(workflow_key,version),
  check (status<>'active' or (approved_by_user_id is not null and activated_at is not null))
);
create unique index mme_workflow_one_active_version_idx
  on public.mme_workflow_definitions(workflow_key) where status='active';

create table public.mme_workflow_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  schema_version integer not null default 1 check (schema_version>0),
  producer text not null check (length(btrim(producer)) between 2 and 100),
  entity_type text not null check (entity_type ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  entity_id text not null check (length(entity_id) between 1 and 180),
  entity_version text,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  correlation_id text,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  idempotency_key text not null unique check (length(btrim(idempotency_key)) between 8 and 240),
  processing_status text not null default 'accepted'
    check (processing_status in ('accepted','matched','ignored','rejected')),
  created_by_service text not null
);
create index mme_workflow_events_type_received_idx
  on public.mme_workflow_events(event_type,received_at desc);

create table public.mme_workflow_executions (
  id uuid primary key default gen_random_uuid(),
  workflow_definition_id uuid not null references public.mme_workflow_definitions(id) on delete restrict,
  workflow_key text not null,
  workflow_version integer not null,
  event_id uuid not null references public.mme_workflow_events(id) on delete restrict,
  correlation_id text,
  execution_status text not null default 'queued'
    check (execution_status in ('queued','running','paused','succeeded','failed','dead_letter','cancelled')),
  current_step_key text,
  attempt_count integer not null default 0 check (attempt_count>=0),
  max_attempts integer not null default 8 check (max_attempts between 1 and 20),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  lease_expires_at timestamptz,
  last_error_code text,
  last_error_summary text check (last_error_summary is null or length(last_error_summary)<=1000),
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  unique(workflow_definition_id,event_id),
  check ((locked_at is null)=(locked_by is null)),
  check (execution_status<>'running' or locked_at is not null)
);
create index mme_workflow_execution_claim_idx
  on public.mme_workflow_executions(available_at,created_at)
  where execution_status in ('queued','failed','running');

create table public.mme_workflow_step_runs (
  id bigint generated always as identity primary key,
  execution_id uuid not null references public.mme_workflow_executions(id) on delete restrict,
  step_key text not null check (step_key ~ '^[a-z][a-z0-9_.-]{1,95}$'),
  step_order integer not null check (step_order>=0),
  step_type text not null check (step_type in ('module_command','create_task','request_approval','notify','wait','condition')),
  step_status text not null default 'pending'
    check (step_status in ('pending','running','succeeded','retrying','failed','skipped','compensating','compensated')),
  attempt_count integer not null default 0 check (attempt_count>=0),
  input_reference jsonb not null default '{}'::jsonb check (jsonb_typeof(input_reference)='object'),
  output_reference jsonb not null default '{}'::jsonb check (jsonb_typeof(output_reference)='object'),
  last_error_code text,
  last_error_summary text check (last_error_summary is null or length(last_error_summary)<=1000),
  started_at timestamptz,
  finished_at timestamptz,
  unique(execution_id,step_key),
  unique(execution_id,step_order)
);

create table public.mme_workflow_execution_events (
  id bigint generated always as identity primary key,
  execution_id uuid not null references public.mme_workflow_executions(id) on delete restrict,
  step_run_id bigint references public.mme_workflow_step_runs(id) on delete restrict,
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_.-]{1,95}$'),
  actor_service text not null,
  event_data jsonb not null default '{}'::jsonb check (jsonb_typeof(event_data)='object'),
  created_at timestamptz not null default now()
);
create index mme_workflow_execution_events_idx
  on public.mme_workflow_execution_events(execution_id,created_at);

alter table public.mme_workflow_definitions enable row level security;
alter table public.mme_workflow_definitions force row level security;
alter table public.mme_workflow_events enable row level security;
alter table public.mme_workflow_events force row level security;
alter table public.mme_workflow_executions enable row level security;
alter table public.mme_workflow_executions force row level security;
alter table public.mme_workflow_step_runs enable row level security;
alter table public.mme_workflow_step_runs force row level security;
alter table public.mme_workflow_execution_events enable row level security;
alter table public.mme_workflow_execution_events force row level security;
revoke all on public.mme_workflow_definitions,public.mme_workflow_events,
  public.mme_workflow_executions,public.mme_workflow_step_runs,
  public.mme_workflow_execution_events from public,anon,authenticated;
grant all on public.mme_workflow_definitions,public.mme_workflow_events,
  public.mme_workflow_executions,public.mme_workflow_step_runs,
  public.mme_workflow_execution_events to service_role;

create function public.mme_register_workflow_event(
  p_event_type text,p_schema_version integer,p_producer text,
  p_entity_type text,p_entity_id text,p_entity_version text,
  p_occurred_at timestamptz,p_correlation_id text,p_payload jsonb,
  p_idempotency_key text,p_service_identity text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if p_event_type is null or p_event_type !~ '^[a-z][a-z0-9_.-]{1,127}$'
     or p_schema_version is null or p_schema_version<1
     or p_producer is null or length(btrim(p_producer)) not between 2 and 100
     or p_entity_type is null or p_entity_type !~ '^[a-z][a-z0-9_.-]{1,63}$'
     or p_entity_id is null or length(p_entity_id) not between 1 and 180
     or p_occurred_at is null or p_payload is null or jsonb_typeof(p_payload)<>'object'
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 8 and 240
     or p_service_identity is null or length(btrim(p_service_identity)) not between 2 and 100 then
    raise exception 'Invalid workflow event envelope' using errcode='22023';
  end if;

  insert into public.mme_workflow_events(
    event_type,schema_version,producer,entity_type,entity_id,entity_version,
    occurred_at,correlation_id,payload,idempotency_key,created_by_service
  ) values (
    p_event_type,p_schema_version,btrim(p_producer),p_entity_type,p_entity_id,p_entity_version,
    p_occurred_at,p_correlation_id,p_payload,btrim(p_idempotency_key),btrim(p_service_identity)
  ) on conflict(idempotency_key) do nothing returning id into v_id;

  if v_id is null then
    select id into v_id from public.mme_workflow_events where idempotency_key=btrim(p_idempotency_key);
  end if;
  return v_id;
end;
$$;

create function public.mme_match_workflow_event(p_event_id uuid,p_worker_identity text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_event public.mme_workflow_events%rowtype; v_count integer:=0; v_definition record;
begin
  if p_event_id is null or p_worker_identity is null or length(btrim(p_worker_identity)) not between 2 and 100 then
    raise exception 'Invalid workflow matching request' using errcode='22023';
  end if;
  select * into v_event from public.mme_workflow_events where id=p_event_id for update;
  if not found then raise exception 'Workflow event not found' using errcode='P0002'; end if;
  if v_event.processing_status<>'accepted' then
    select count(*) into v_count from public.mme_workflow_executions where event_id=p_event_id;
    return v_count;
  end if;

  for v_definition in
    select * from public.mme_workflow_definitions
     where trigger_event_type=v_event.event_type and status='active'
  loop
    insert into public.mme_workflow_executions(
      workflow_definition_id,workflow_key,workflow_version,event_id,correlation_id
    ) values (
      v_definition.id,v_definition.workflow_key,v_definition.version,p_event_id,v_event.correlation_id
    ) on conflict(workflow_definition_id,event_id) do nothing;
    if found then v_count:=v_count+1; end if;
  end loop;

  update public.mme_workflow_events
     set processing_status=case when v_count>0 then 'matched' else 'ignored' end
   where id=p_event_id;
  return v_count;
end;
$$;

create function public.mme_claim_workflow_executions(
  p_worker_identity text,p_batch_size integer default 10,p_lease_seconds integer default 120
)
returns setof public.mme_workflow_executions
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_worker_identity is null or length(btrim(p_worker_identity)) not between 2 and 100
     or p_batch_size is null or p_batch_size not between 1 and 50
     or p_lease_seconds is null or p_lease_seconds not between 30 and 900 then
    raise exception 'Invalid workflow claim parameters' using errcode='22023';
  end if;

  return query
  with picked as (
    select id from public.mme_workflow_executions
     where available_at<=now()
       and (
         execution_status in ('queued','failed')
         or (execution_status='running' and lease_expires_at<now())
       )
       and attempt_count<max_attempts
     order by available_at,created_at
     for update skip locked
     limit p_batch_size
  )
  update public.mme_workflow_executions e
     set execution_status='running',locked_at=now(),locked_by=btrim(p_worker_identity),
         lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
         attempt_count=attempt_count+1,started_at=coalesce(started_at,now())
    from picked where e.id=picked.id
  returning e.*;
end;
$$;

create function public.mme_finish_workflow_execution(
  p_execution_id uuid,p_worker_identity text,p_success boolean,
  p_error_code text default null,p_error_summary text default null,
  p_retry_delay_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_execution public.mme_workflow_executions%rowtype; v_next_status text;
begin
  if p_execution_id is null or p_worker_identity is null
     or p_success is null or p_retry_delay_seconds is null
     or p_retry_delay_seconds not between 1 and 86400
     or coalesce(length(p_error_summary),0)>1000 then
    raise exception 'Invalid workflow completion request' using errcode='22023';
  end if;

  select * into v_execution from public.mme_workflow_executions
   where id=p_execution_id for update;
  if not found or v_execution.execution_status<>'running'
     or v_execution.locked_by<>btrim(p_worker_identity)
     or v_execution.lease_expires_at<now() then
    raise exception 'Workflow execution lease is not owned by this worker' using errcode='42501';
  end if;

  if p_success then
    v_next_status:='succeeded';
  elsif v_execution.attempt_count>=v_execution.max_attempts then
    v_next_status:='dead_letter';
  else
    v_next_status:='failed';
  end if;

  update public.mme_workflow_executions
     set execution_status=v_next_status,
         available_at=case when v_next_status='failed'
           then now()+make_interval(secs=>p_retry_delay_seconds) else available_at end,
         last_error_code=case when p_success then null else left(p_error_code,120) end,
         last_error_summary=case when p_success then null else p_error_summary end,
         locked_at=null,locked_by=null,lease_expires_at=null,
         finished_at=case when v_next_status in ('succeeded','dead_letter') then now() else null end
   where id=p_execution_id;

  insert into public.mme_workflow_execution_events(
    execution_id,event_type,actor_service,event_data
  ) values (
    p_execution_id,'execution.'||v_next_status,btrim(p_worker_identity),
    jsonb_build_object('attempt',v_execution.attempt_count,'error_code',p_error_code)
  );
  return true;
end;
$$;

revoke all on function public.mme_register_workflow_event(text,integer,text,text,text,text,timestamptz,text,jsonb,text,text)
  from public,anon,authenticated;
revoke all on function public.mme_match_workflow_event(uuid,text) from public,anon,authenticated;
revoke all on function public.mme_claim_workflow_executions(text,integer,integer) from public,anon,authenticated;
revoke all on function public.mme_finish_workflow_execution(uuid,text,boolean,text,text,integer)
  from public,anon,authenticated;
grant execute on function public.mme_register_workflow_event(text,integer,text,text,text,text,timestamptz,text,jsonb,text,text) to service_role;
grant execute on function public.mme_match_workflow_event(uuid,text) to service_role;
grant execute on function public.mme_claim_workflow_executions(text,integer,integer) to service_role;
grant execute on function public.mme_finish_workflow_execution(uuid,text,boolean,text,text,integer) to service_role;

create function public.mme_workflow_execution_events_immutable()
returns trigger language plpgsql set search_path=''
as $$ begin raise exception 'Workflow execution events are append-only'; end; $$;
create trigger mme_workflow_execution_events_no_update_delete
before update or delete on public.mme_workflow_execution_events
for each row execute function public.mme_workflow_execution_events_immutable();
revoke all on function public.mme_workflow_execution_events_immutable() from public,anon,authenticated;

comment on table public.mme_workflow_definitions is
  'Build 006 versioned workflow definitions. Active versions are unique by workflow key; activation approval is required.';
comment on table public.mme_workflow_events is
  'Build 006 durable, idempotent event inbox; payloads must be minimized and contain no credentials or unnecessary personal data.';
comment on table public.mme_workflow_executions is
  'Build 006 durable workflow execution queue with bounded attempts and worker leases; actions must call authorized module APIs.';
comment on table public.mme_workflow_step_runs is
  'Build 006 per-step execution outcomes and retry evidence; no direct source-module transaction writes.';
commit;
