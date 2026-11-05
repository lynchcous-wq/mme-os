-- Build 006: route final step completion through the authoritative execution gate.
begin;

create or replace function public.mme_complete_workflow_step(
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
    -- Delegate terminal success to the authoritative completion gate.
    perform public.mme_finish_workflow_execution(
      v_execution.id,btrim(p_worker_identity),true,null,null,60
    );
  end if;

  return v_status;
end;
$$;

comment on function public.mme_complete_workflow_step(bigint,text,boolean,jsonb,text,text,integer) is
  'Records step outcome and bounded retry; delegates terminal success to mme_finish_workflow_execution so every step must pass the authoritative completion gate.';

commit;
