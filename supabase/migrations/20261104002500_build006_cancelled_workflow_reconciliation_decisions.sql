-- Build 006: append-only supervisor findings for cancelled in-flight workflow steps.
-- This ledger records investigation outcomes only; it never resumes or mutates workflow execution.
begin;

create table public.mme_workflow_cancellation_reconciliation_decisions (
  id bigint generated always as identity primary key,
  execution_id uuid not null,
  step_run_id bigint not null,
  outcome text not null check (outcome in (
    'confirmed_completed','confirmed_not_completed',
    'compensation_verified','unresolved_escalated'
  )),
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  evidence_references jsonb not null check (
    jsonb_typeof(evidence_references)='array'
    and jsonb_array_length(evidence_references) between 1 and 20
    and length(evidence_references::text)<=8000
  ),
  decided_by_user_id uuid not null references auth.users(id) on delete restrict,
  decided_at timestamptz not null default now(),
  foreign key (step_run_id,execution_id)
    references public.mme_workflow_step_runs(id,execution_id) on delete restrict
);

create index mme_workflow_cancel_recon_decisions_step_idx
  on public.mme_workflow_cancellation_reconciliation_decisions(step_run_id,decided_at desc);
create unique index mme_workflow_cancel_recon_one_final_outcome_idx
  on public.mme_workflow_cancellation_reconciliation_decisions(step_run_id)
  where outcome <> 'unresolved_escalated';

alter table public.mme_workflow_cancellation_reconciliation_decisions enable row level security;
alter table public.mme_workflow_cancellation_reconciliation_decisions force row level security;
revoke all on public.mme_workflow_cancellation_reconciliation_decisions from public,anon,authenticated,service_role;

create function public.mme_guard_cancellation_reconciliation_decision()
returns trigger language plpgsql set search_path=''
as $$
begin
  raise exception 'Cancellation reconciliation decisions are append-only';
end;
$$;

create trigger mme_workflow_cancel_recon_decision_immutable
before update or delete on public.mme_workflow_cancellation_reconciliation_decisions
for each row execute function public.mme_guard_cancellation_reconciliation_decision();

create function public.mme_record_cancelled_workflow_reconciliation_decision(
  p_actor_user_id uuid,
  p_step_run_id bigint,
  p_outcome text,
  p_reason text,
  p_evidence_references jsonb
)
returns bigint language plpgsql security definer set search_path=''
as $$
declare
  v_step public.mme_workflow_step_runs%rowtype;
  v_execution public.mme_workflow_executions%rowtype;
  v_definition public.mme_workflow_definitions%rowtype;
  v_decision_id bigint;
begin
  if p_actor_user_id is null or p_step_run_id is null
     or p_outcome not in ('confirmed_completed','confirmed_not_completed',
       'compensation_verified','unresolved_escalated')
     or p_reason is null or length(btrim(p_reason)) not between 3 and 1000
     or p_evidence_references is null
     or jsonb_typeof(p_evidence_references)<>'array'
     or jsonb_array_length(p_evidence_references) not between 1 and 20
     or length(p_evidence_references::text)>8000 then
    raise exception 'Invalid cancellation reconciliation decision' using errcode='22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_evidence_references) e
     where jsonb_typeof(e)<>'object'
        or jsonb_typeof(e->'kind')<>'string'
        or length(btrim(e->>'kind')) not between 2 and 80
        or jsonb_typeof(e->'reference')<>'string'
        or length(btrim(e->>'reference')) not between 1 and 500
        or (e ? 'sha256' and (
          jsonb_typeof(e->'sha256')<>'string'
          or (e->>'sha256') !~ '^[0-9a-f]{64}$'
        ))
  ) then
    raise exception 'Evidence must contain kind and opaque reference; optional sha256 must be a lowercase 64-character digest'
      using errcode='22023';
  end if;

  select * into v_step from public.mme_workflow_step_runs
   where id=p_step_run_id for update;
  if not found or v_step.step_status<>'manual_review'
     or v_step.recovery_reason<>'workflow_cancelled_during_step_execution' then
    raise exception 'Step is not awaiting cancelled-workflow reconciliation' using errcode='55000';
  end if;

  select * into v_execution from public.mme_workflow_executions
   where id=v_step.execution_id for update;
  if not found or v_execution.execution_status<>'cancelled' then
    raise exception 'Parent workflow is not terminally cancelled' using errcode='55000';
  end if;

  select * into v_definition from public.mme_workflow_definitions
   where id=v_execution.workflow_definition_id;
  if not found then raise exception 'Workflow definition not found' using errcode='P0002'; end if;

  if p_actor_user_id=v_definition.created_by_user_id then
    raise exception 'Workflow author cannot reconcile their own workflow execution' using errcode='42501';
  end if;
  if not public.mme_employee_authorize_task_action(
    p_actor_user_id,'tasks.workflow.review',v_definition.owner_department,null
  ) then
    raise exception 'Not authorized to reconcile this workflow step' using errcode='42501';
  end if;

  if exists (
    select 1 from public.mme_workflow_cancellation_reconciliation_decisions d
     where d.step_run_id=p_step_run_id and d.outcome<>'unresolved_escalated'
  ) then
    raise exception 'A final reconciliation outcome has already been recorded' using errcode='55000';
  end if;

  insert into public.mme_workflow_cancellation_reconciliation_decisions(
    execution_id,step_run_id,outcome,reason,evidence_references,decided_by_user_id
  ) values (
    v_execution.id,v_step.id,p_outcome,left(btrim(p_reason),1000),
    p_evidence_references,p_actor_user_id
  ) returning id into v_decision_id;

  insert into public.mme_workflow_execution_events(
    execution_id,step_run_id,event_type,actor_service,event_data
  ) values (
    v_execution.id,v_step.id,'step.cancellation_reconciliation_decided',
    p_actor_user_id::text,
    jsonb_build_object('decision_id',v_decision_id,'outcome',p_outcome,
      'reason',left(btrim(p_reason),1000),'evidence_references',p_evidence_references,
      'reviewer_user_id',p_actor_user_id,'workflow_remains_cancelled',true,
      'step_status_unchanged',true,'retry_or_resume_authorized',false)
  );

  return v_decision_id;
end;
$$;

revoke all on function public.mme_guard_cancellation_reconciliation_decision()
  from public,anon,authenticated,service_role;
revoke all on function public.mme_record_cancelled_workflow_reconciliation_decision(uuid,bigint,text,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.mme_record_cancelled_workflow_reconciliation_decision(uuid,bigint,text,text,jsonb)
  to service_role;

comment on table public.mme_workflow_cancellation_reconciliation_decisions is
  'Append-only supervisor findings for cancelled in-flight workflow steps. Evidence references are opaque identifiers, not proof that referenced artifacts were independently validated.';
comment on function public.mme_record_cancelled_workflow_reconciliation_decision(uuid,bigint,text,text,jsonb) is
  'Records an authorized supervisor finding and audit event for a cancelled in-flight step. It never changes workflow or step status and never authorizes retry, compensation, or resume.';

commit;
