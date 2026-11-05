-- Build 006: expose immutable reconciliation decisions in the authorized supervisor inbox.
begin;

create or replace function public.mme_list_cancelled_workflow_reconciliations(
  p_actor_user_id uuid,
  p_limit integer default 50
)
returns setof jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_row record;
begin
  if p_actor_user_id is null or p_limit is null or p_limit not between 1 and 100 then
    raise exception 'Invalid workflow reconciliation inbox request' using errcode='22023';
  end if;

  for v_row in
    select s.id as step_run_id,s.execution_id,s.step_key,s.step_type,s.step_status,
           s.attempt_count,s.max_attempts,s.recovery_reason,s.compensation_status,
           s.recovery_policy,s.idempotency_key,s.started_at,s.finished_at,
           e.workflow_key,e.workflow_version,e.execution_status,e.correlation_id,
           e.last_error_code,e.last_error_summary,e.created_at as execution_created_at,
           d.display_name,d.owner_department,
           coalesce((
             select jsonb_agg(jsonb_build_object(
               'event_type',ev.event_type,'actor',ev.actor_service,
               'event_data',ev.event_data,'created_at',ev.created_at
             ) order by ev.created_at desc)
             from public.mme_workflow_execution_events ev
             where ev.execution_id=e.id and (ev.step_run_id=s.id or ev.step_run_id is null)
           ),'[]'::jsonb) as audit_history,
           coalesce((
             select jsonb_agg(jsonb_build_object(
               'id',rd.id,'outcome',rd.outcome,'reason',rd.reason,
               'evidence_references',rd.evidence_references,
               'decided_by_user_id',rd.decided_by_user_id,
               'decided_at',rd.decided_at
             ) order by rd.decided_at asc,rd.id asc)
             from public.mme_workflow_cancellation_reconciliation_decisions rd
             where rd.execution_id=e.id and rd.step_run_id=s.id
           ),'[]'::jsonb) as decision_history
      from public.mme_workflow_step_runs s
      join public.mme_workflow_executions e on e.id=s.execution_id
      join public.mme_workflow_definitions d on d.id=e.workflow_definition_id
     where s.step_status='manual_review'
       and e.execution_status='cancelled'
       and s.recovery_reason='workflow_cancelled_during_step_execution'
       and public.mme_employee_authorize_task_action(
         p_actor_user_id,'tasks.workflow.review',d.owner_department,null
       )
     order by e.finished_at desc,s.step_order asc
     limit p_limit
  loop
    return next jsonb_build_object(
      'step_run_id',v_row.step_run_id,'execution_id',v_row.execution_id,
      'workflow_key',v_row.workflow_key,'workflow_name',v_row.display_name,
      'workflow_version',v_row.workflow_version,'department',v_row.owner_department,
      'step_key',v_row.step_key,'step_type',v_row.step_type,'step_status',v_row.step_status,
      'attempt_count',v_row.attempt_count,'max_attempts',v_row.max_attempts,
      'recovery_reason',v_row.recovery_reason,'recovery_policy',v_row.recovery_policy,
      'compensation_status',v_row.compensation_status,'idempotency_key',v_row.idempotency_key,
      'last_error_code',v_row.last_error_code,'last_error_summary',v_row.last_error_summary,
      'correlation_id',v_row.correlation_id,'execution_created_at',v_row.execution_created_at,
      'audit_history',v_row.audit_history,'decision_history',v_row.decision_history
    );
  end loop;
end;
$$;

revoke all on function public.mme_list_cancelled_workflow_reconciliations(uuid,integer)
  from public,anon,authenticated;
grant execute on function public.mme_list_cancelled_workflow_reconciliations(uuid,integer)
  to service_role;

comment on function public.mme_list_cancelled_workflow_reconciliations(uuid,integer) is
  'Read-only authorized supervisor inbox for cancelled in-flight workflow steps, including append-only decision and evidence-reference history. Does not resume or mutate executions.';

commit;
