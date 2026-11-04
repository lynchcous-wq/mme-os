-- Build 006: recover abandoned workflow worker leases, including exhausted final attempts.
begin;

create function public.mme_reap_expired_workflow_leases(
  p_reaper_identity text,
  p_batch_size integer default 100
)
returns table(recovered_count integer,dead_lettered_count integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_recovered integer:=0;
  v_dead_lettered integer:=0;
  v_next_status text;
  v_delay_seconds integer;
begin
  if p_reaper_identity is null
     or length(btrim(p_reaper_identity)) not between 2 and 100
     or p_batch_size is null or p_batch_size not between 1 and 500 then
    raise exception 'Invalid workflow lease reaper parameters' using errcode='22023';
  end if;

  for v_row in
    select id,attempt_count,max_attempts
      from public.mme_workflow_executions
     where execution_status='running'
       and lease_expires_at is not null
       and lease_expires_at<=now()
     order by lease_expires_at,created_at
     for update skip locked
     limit p_batch_size
  loop
    if v_row.attempt_count>=v_row.max_attempts then
      v_next_status:='dead_letter';
      v_delay_seconds:=0;
      v_dead_lettered:=v_dead_lettered+1;
    else
      v_next_status:='failed';
      -- Bounded exponential delay: 30s, 60s, 120s ... capped at 6h.
      v_delay_seconds:=least(21600,30 * (2 ^ least(greatest(v_row.attempt_count-1,0),10))::integer);
      v_recovered:=v_recovered+1;
    end if;

    update public.mme_workflow_executions
       set execution_status=v_next_status,
           available_at=case when v_next_status='failed'
             then now()+make_interval(secs=>v_delay_seconds) else available_at end,
           last_error_code='worker_lease_expired',
           last_error_summary='Worker lease expired before the execution was completed',
           locked_at=null,locked_by=null,lease_expires_at=null,
           finished_at=case when v_next_status='dead_letter' then now() else null end
     where id=v_row.id;

    insert into public.mme_workflow_execution_events(
      execution_id,event_type,actor_service,event_data
    ) values (
      v_row.id,'execution.'||v_next_status,btrim(p_reaper_identity),
      jsonb_build_object(
        'reason','worker_lease_expired',
        'attempt',v_row.attempt_count,
        'retry_delay_seconds',v_delay_seconds
      )
    );
  end loop;

  return query select v_recovered,v_dead_lettered;
end;
$$;

revoke all on function public.mme_reap_expired_workflow_leases(text,integer)
  from public,anon,authenticated;
grant execute on function public.mme_reap_expired_workflow_leases(text,integer)
  to service_role;

comment on function public.mme_reap_expired_workflow_leases(text,integer) is
  'Build 006 recovery sweep. Reclaims expired worker leases, applies bounded exponential backoff, and dead-letters executions whose final attempt expired without completion.';

commit;
