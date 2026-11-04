-- Build 006: prevent execution success while any workflow step remains incomplete.
begin;

create or replace function public.mme_finish_workflow_execution(
  p_execution_id uuid,p_worker_identity text,p_success boolean,
  p_error_code text default null,p_error_summary text default null,
  p_retry_delay_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_execution public.mme_workflow_executions%rowtype;
  v_next_status text;
  v_total_steps integer;
  v_incomplete_steps integer;
begin
  if p_execution_id is null or p_worker_identity is null
     or length(btrim(p_worker_identity)) not between 2 and 100
     or p_success is null or p_retry_delay_seconds is null
     or p_retry_delay_seconds not between 1 and 86400
     or coalesce(length(p_error_summary),0)>1000 then
    raise exception 'Invalid workflow completion request' using errcode='22023';
  end if;

  select * into v_execution from public.mme_workflow_executions
   where id=p_execution_id for update;
  if not found or v_execution.execution_status<>'running'
     or v_execution.locked_by<>btrim(p_worker_identity)
     or v_execution.lease_expires_at<=now() then
    raise exception 'Workflow execution lease is not owned by this worker' using errcode='42501';
  end if;

  if p_success then
    select count(*),
           count(*) filter (where step_status not in ('succeeded','skipped'))
      into v_total_steps,v_incomplete_steps
      from public.mme_workflow_step_runs
     where execution_id=p_execution_id;

    if v_total_steps=0 or v_incomplete_steps>0 then
      raise exception 'Workflow cannot succeed until every step is succeeded or skipped'
        using errcode='55000';
    end if;
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
    jsonb_build_object('attempt',v_execution.attempt_count,
      'error_code',p_error_code,'total_steps',v_total_steps,
      'incomplete_steps',v_incomplete_steps)
  );
  return true;
end;
$$;

comment on function public.mme_finish_workflow_execution(uuid,text,boolean,text,text,integer) is
  'Finishes only a currently leased execution. Success is rejected unless at least one step exists and every step is succeeded or skipped; failure retry/dead-letter behavior remains bounded.';

commit;
