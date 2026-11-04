-- Build 006: preserve terminal abandonment and allow one audited resume beyond execution attempts.
begin;

alter table public.mme_workflow_executions
  add column manual_review_resume_authorized boolean not null default false;

create or replace function public.mme_claim_workflow_executions(
  p_worker_identity text,p_batch_size integer default 10,p_lease_seconds integer default 120
)
returns setof public.mme_workflow_executions
language plpgsql
security definer
set search_path=''
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
         (
           execution_status in ('queued','failed')
           and attempt_count<max_attempts
         )
         or (
           execution_status='queued'
           and manual_review_resume_authorized=true
         )
         or (execution_status='running' and lease_expires_at<now())
       )
     order by available_at,created_at
     for update skip locked
     limit p_batch_size
  )
  update public.mme_workflow_executions e
     set execution_status='running',locked_at=now(),locked_by=btrim(p_worker_identity),
         lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
         attempt_count=attempt_count+1,started_at=coalesce(started_at,now()),
         manual_review_resume_authorized=false
    from picked where e.id=picked.id
  returning e.*;
end;
$$;

create or replace function public.mme_review_workflow_step(
  p_actor_user_id uuid,
  p_step_run_id bigint,
  p_resolution text,
  p_reason text,
  p_evidence jsonb default '{}'::jsonb
)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare
  v_step public.mme_workflow_step_runs%rowtype;
  v_execution public.mme_workflow_executions%rowtype;
  v_definition public.mme_workflow_definitions%rowtype;
  v_next_execution_status text;
begin
  if p_actor_user_id is null or p_step_run_id is null
     or p_resolution not in ('confirmed_succeeded','safe_to_retry','abandoned')
     or p_reason is null or length(btrim(p_reason)) not between 3 and 1000
     or p_evidence is null or jsonb_typeof(p_evidence)<>'object'
     or length(p_evidence::text)>8000 then
    raise exception 'Invalid workflow recovery review' using errcode='22023';
  end if;

  if p_resolution in ('confirmed_succeeded','safe_to_retry')
     and p_evidence='{}'::jsonb then
    raise exception 'Non-empty evidence is required for confirmation or retry authorization'
      using errcode='22023';
  end if;

  select * into v_step from public.mme_workflow_step_runs
   where id=p_step_run_id for update;
  if not found or v_step.step_status<>'manual_review' then
    raise exception 'Step is not awaiting manual review' using errcode='55000';
  end if;

  select * into v_execution from public.mme_workflow_executions
   where id=v_step.execution_id for update;
  if not found or v_execution.execution_status<>'paused' then
    raise exception 'Parent workflow is not paused for review' using errcode='55000';
  end if;

  select * into v_definition from public.mme_workflow_definitions
   where id=v_execution.workflow_definition_id;
  if not found then raise exception 'Workflow definition not found' using errcode='P0002'; end if;

  if p_actor_user_id=v_definition.created_by_user_id then
    raise exception 'Workflow author cannot review their own workflow recovery' using errcode='42501';
  end if;
  if not public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.workflow.review',v_definition.owner_department,null
  ) then
    raise exception 'Not authorized to review workflow recovery' using errcode='42501';
  end if;

  if p_resolution='safe_to_retry' and v_step.attempt_count>=v_step.max_attempts then
    raise exception 'Step retry ceiling has been reached; create a new workflow version or resolve manually' using errcode='55000';
  end if;

  update public.mme_workflow_step_runs
     set recovery_resolution=p_resolution,
         recovery_review_evidence=p_evidence,
         recovery_reviewed_at=now(),
         recovery_reviewed_by=p_actor_user_id::text,
         recovery_reason=left(btrim(p_reason),1000),
         step_status=case p_resolution
           when 'confirmed_succeeded' then 'succeeded'
           when 'safe_to_retry' then 'retrying'
           else 'failed' end,
         recovery_policy=case when p_resolution='safe_to_retry' then 'safe_retry' else recovery_policy end,
         available_at=case when p_resolution='safe_to_retry' then now() else available_at end,
         output_reference=case when p_resolution='confirmed_succeeded'
           then jsonb_build_object('human_review_confirmed',true,'review_evidence',p_evidence)
           else output_reference end,
         locked_at=null,locked_by=null,lease_expires_at=null,
         finished_at=case when p_resolution in ('confirmed_succeeded','abandoned') then now() else null end
   where id=p_step_run_id;

  if p_resolution='abandoned' then
    v_next_execution_status:='dead_letter';
  else
    v_next_execution_status:='queued';
  end if;

  update public.mme_workflow_executions
     set execution_status=v_next_execution_status,
         available_at=now(),locked_at=null,locked_by=null,lease_expires_at=null,
         manual_review_resume_authorized=(p_resolution in ('confirmed_succeeded','safe_to_retry')),
         finished_at=case when v_next_execution_status='dead_letter' then now() else null end,
         last_error_code=case when v_next_execution_status='dead_letter' then 'step_abandoned_after_review' else null end,
         last_error_summary=case when v_next_execution_status='dead_letter'
           then 'Workflow step was abandoned by an authorized reviewer' else null end
   where id=v_execution.id;

  insert into public.mme_workflow_execution_events(
    execution_id,step_run_id,event_type,actor_service,event_data
  ) values (
    v_execution.id,v_step.id,'step.recovery_reviewed',p_actor_user_id::text,
    jsonb_build_object('resolution',p_resolution,'reason',left(btrim(p_reason),1000),
      'evidence',p_evidence,'reviewer_user_id',p_actor_user_id,
      'execution_attempt_ceiling_bypassed',(
        p_resolution in ('confirmed_succeeded','safe_to_retry')
        and v_execution.attempt_count>=v_execution.max_attempts
      ))
  );

  return v_next_execution_status;
end;
$$;

comment on column public.mme_workflow_executions.manual_review_resume_authorized is
  'One-time server-set authorization consumed atomically by the execution claimant after an approved human recovery review. Does not reset attempt counters.';
comment on function public.mme_claim_workflow_executions(text,integer,integer) is
  'Claims due executions with bounded leases. A single supervisor-approved recovery resume may proceed beyond the normal execution attempt ceiling; authorization is consumed atomically.';
comment on function public.mme_review_workflow_step(uuid,bigint,text,text,jsonb) is
  'Independent human recovery review. Confirmation/retry require non-empty evidence; approved resume is one-time; abandonment enters terminal dead_letter state.';

commit;
