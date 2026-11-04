-- Build 006: explicit workflow cancellation with lease invalidation and side-effect review.
begin;

alter table public.mme_workflow_step_runs
  drop constraint if exists mme_workflow_step_runs_step_status_check;
alter table public.mme_workflow_step_runs
  add constraint mme_workflow_step_runs_step_status_check
  check (step_status in (
    'pending','running','succeeded','retrying','failed','skipped',
    'compensating','compensated','manual_review','cancelled'
  ));

create function public.mme_cancel_workflow_execution(
  p_actor_user_id uuid,
  p_execution_id uuid,
  p_reason text
)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare
  v_execution public.mme_workflow_executions%rowtype;
  v_definition public.mme_workflow_definitions%rowtype;
  v_running_count integer:=0;
  v_queued_count integer:=0;
begin
  if p_actor_user_id is null or p_execution_id is null
     or p_reason is null or length(btrim(p_reason)) not between 3 and 1000 then
    raise exception 'Invalid workflow cancellation request' using errcode='22023';
  end if;

  select * into v_execution
    from public.mme_workflow_executions
   where id=p_execution_id for update;
  if not found then raise exception 'Workflow execution not found' using errcode='P0002'; end if;

  if v_execution.execution_status not in ('queued','running','paused','failed') then
    raise exception 'Workflow execution is already terminal and cannot be cancelled'
      using errcode='55000';
  end if;

  select * into v_definition
    from public.mme_workflow_definitions
   where id=v_execution.workflow_definition_id;
  if not found then raise exception 'Workflow definition not found' using errcode='P0002'; end if;

  if not public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.workflow.review',v_definition.owner_department,null
  ) then
    raise exception 'Not authorized to cancel this workflow execution' using errcode='42501';
  end if;

  select count(*) filter (where step_status='running'),
         count(*) filter (where step_status in ('pending','retrying'))
    into v_running_count,v_queued_count
    from public.mme_workflow_step_runs
   where execution_id=p_execution_id;

  -- A running handler may already have caused an external side effect.
  -- Stop its lease and require review; do not claim that cancellation undid it.
  update public.mme_workflow_step_runs
     set step_status=case
           when step_status='running' then 'manual_review'
           when step_status in ('pending','retrying') then 'cancelled'
           else step_status end,
         recovery_reason=case when step_status='running'
           then 'workflow_cancelled_during_step_execution'
           else recovery_reason end,
         compensation_status=case
           when step_status='running'
             and step_type in ('module_command','create_task','request_approval','notify')
             then 'manual_review'
           else compensation_status end,
         locked_at=null,locked_by=null,lease_expires_at=null,
         finished_at=case when step_status in ('pending','retrying') then now() else finished_at end
   where execution_id=p_execution_id
     and step_status in ('running','pending','retrying');

  update public.mme_workflow_executions
     set execution_status='cancelled',
         manual_review_resume_authorized=false,
         locked_at=null,locked_by=null,lease_expires_at=null,
         finished_at=now(),
         last_error_code='cancelled_by_authorized_user',
         last_error_summary=left(btrim(p_reason),1000)
   where id=p_execution_id;

  insert into public.mme_workflow_execution_events(
    execution_id,event_type,actor_service,event_data
  ) values (
    p_execution_id,'execution.cancelled',p_actor_user_id::text,
    jsonb_build_object(
      'reason',left(btrim(p_reason),1000),
      'running_steps_requiring_review',v_running_count,
      'not_started_steps_cancelled',v_queued_count,
      'active_execution_lease_invalidated',v_execution.locked_by is not null
    )
  );

  return 'cancelled';
end;
$$;

revoke all on function public.mme_cancel_workflow_execution(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.mme_cancel_workflow_execution(uuid,uuid,text)
  to service_role;

comment on function public.mme_cancel_workflow_execution(uuid,uuid,text) is
  'Cancels a nonterminal workflow under supervisor permission. Invalidates execution and step leases, cancels not-started steps, and routes in-flight steps to manual review because external side effects may already have occurred.';

commit;
