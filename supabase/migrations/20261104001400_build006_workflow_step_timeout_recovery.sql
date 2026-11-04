-- Build 006: recover timed-out steps conservatively and prevent blind replay of side effects.
begin;

alter table public.mme_workflow_step_runs
  drop constraint if exists mme_workflow_step_runs_step_status_check;
alter table public.mme_workflow_step_runs
  add constraint mme_workflow_step_runs_step_status_check
  check (step_status in ('pending','running','succeeded','retrying','failed','skipped','compensating','compensated','manual_review'));

alter table public.mme_workflow_step_runs
  add column recovery_policy text not null default 'manual_review'
    check (recovery_policy in ('safe_retry','manual_review')),
  add column recovery_reason text,
  add column recovery_reviewed_at timestamptz,
  add column recovery_reviewed_by text,
  add column compensation_status text not null default 'not_required'
    check (compensation_status in ('not_required','pending','manual_review','running','succeeded','failed'));

create function public.mme_set_workflow_step_recovery_policy()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  -- Only steps without external side effects are automatically replayable by default.
  if new.step_type in ('wait','condition') then
    new.recovery_policy:='safe_retry';
  else
    new.recovery_policy:='manual_review';
  end if;
  return new;
end;
$$;

create trigger mme_workflow_step_recovery_policy_default
before insert on public.mme_workflow_step_runs
for each row execute function public.mme_set_workflow_step_recovery_policy();

create or replace function public.mme_claim_workflow_step(
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

  select * into v_execution from public.mme_workflow_executions
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
     and s.step_status in ('pending','retrying')
     and s.attempt_count<s.max_attempts
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
     set step_status='running',attempt_count=attempt_count+1,
         locked_at=now(),locked_by=btrim(p_worker_identity),
         lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
         started_at=coalesce(started_at,now())
   where s.id=v_step_id
  returning s.*;
end;
$$;

create function public.mme_reap_expired_workflow_steps(
  p_reaper_identity text,
  p_batch_size integer default 100
)
returns table(retry_scheduled_count integer,manual_review_count integer)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_step record;
  v_next_status text;
  v_delay integer;
  v_retry integer:=0;
  v_review integer:=0;
begin
  if p_reaper_identity is null or length(btrim(p_reaper_identity)) not between 2 and 100
     or p_batch_size is null or p_batch_size not between 1 and 500 then
    raise exception 'Invalid workflow step reaper parameters' using errcode='22023';
  end if;

  for v_step in
    select id,execution_id,step_key,step_type,recovery_policy,attempt_count,max_attempts,
           idempotency_key,compensation_status
      from public.mme_workflow_step_runs
     where step_status='running' and lease_expires_at is not null and lease_expires_at<=now()
     order by lease_expires_at,id
     for update skip locked
     limit p_batch_size
  loop
    if v_step.recovery_policy='safe_retry' and v_step.attempt_count<v_step.max_attempts then
      v_next_status:='retrying';
      v_delay:=least(21600,30 * (2 ^ least(greatest(v_step.attempt_count-1,0),10))::integer);
      v_retry:=v_retry+1;
    else
      v_next_status:='manual_review';
      v_delay:=0;
      v_review:=v_review+1;
    end if;

    update public.mme_workflow_step_runs
       set step_status=v_next_status,
           available_at=case when v_next_status='retrying'
             then now()+make_interval(secs=>v_delay) else available_at end,
           recovery_reason='worker_lease_expired',
           compensation_status=case
             when step_type in ('module_command','create_task','request_approval','notify')
               then 'manual_review' else compensation_status end,
           locked_at=null,locked_by=null,lease_expires_at=null,
           finished_at=case when v_next_status='manual_review' then now() else null end
     where id=v_step.id;

    if v_next_status='manual_review' then
      update public.mme_workflow_executions
         set execution_status='paused',locked_at=null,locked_by=null,lease_expires_at=null,
             last_error_code='step_timeout_manual_review',
             last_error_summary='Step '||v_step.step_key||' timed out; side-effect status requires review'
       where id=v_step.execution_id and execution_status='running';
    end if;

    insert into public.mme_workflow_execution_events(
      execution_id,step_run_id,event_type,actor_service,event_data
    ) values (
      v_step.execution_id,v_step.id,'step.'||v_next_status,btrim(p_reaper_identity),
      jsonb_build_object('reason','worker_lease_expired','step_key',v_step.step_key,
        'step_type',v_step.step_type,'attempt',v_step.attempt_count,
        'idempotency_key',v_step.idempotency_key,'retry_delay_seconds',v_delay,
        'compensation_status',case when v_step.step_type in
          ('module_command','create_task','request_approval','notify')
          then 'manual_review' else v_step.compensation_status end)
    );
  end loop;

  return query select v_retry,v_review;
end;
$$;

revoke all on function public.mme_set_workflow_step_recovery_policy() from public,anon,authenticated;
revoke all on function public.mme_reap_expired_workflow_steps(text,integer) from public,anon,authenticated;
grant execute on function public.mme_reap_expired_workflow_steps(text,integer) to service_role;

comment on column public.mme_workflow_step_runs.recovery_policy is
  'Timeout policy. Only wait/condition steps default to automatic retry; side-effect steps require manual review after an uncertain timeout.';
comment on column public.mme_workflow_step_runs.compensation_status is
  'Compensation tracking state. Timed-out side-effect steps require manual review; this schema does not automatically execute compensations.';
comment on function public.mme_reap_expired_workflow_steps(text,integer) is
  'Reclaims expired step leases. Automatically retries only wait/condition steps; ambiguous side effects pause the parent workflow for human review.';

commit;
