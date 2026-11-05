-- Build 009.19: durable POS hardware command delivery leases and retry scheduling.
begin;
alter table public.mme_pos_drawer_hardware_commands
  add column if not exists dispatch_attempt_count integer not null default 0 check(dispatch_attempt_count between 0 and 1000),
  add column if not exists dispatch_max_attempts integer not null default 5 check(dispatch_max_attempts between 1 and 20),
  add column if not exists next_attempt_at timestamptz not null default now(),
  add column if not exists dispatch_lease_token uuid,
  add column if not exists dispatch_lease_until timestamptz,
  add column if not exists provider_command_id text,
  add column if not exists dispatched_at timestamptz,
  add constraint mme_pos_hw_command_lease_pair check(
    (dispatch_lease_token is null and dispatch_lease_until is null)
    or (dispatch_lease_token is not null and dispatch_lease_until is not null)
  );
create index if not exists mme_pos_hw_command_delivery_queue_idx
  on public.mme_pos_drawer_hardware_commands(next_attempt_at,requested_at)
  where status='requested';

create or replace function public.mme_pos_record_drawer_hardware_command_intent(
  p_device_id uuid,p_drawer_session_id uuid,p_actor_person_id uuid,
  p_command_type text,p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device public.mme_pos_register_devices%rowtype; v_id uuid; v_existing public.mme_pos_drawer_hardware_commands%rowtype;
begin
  if p_device_id is null or p_actor_person_id is null
    or p_command_type not in ('open_drawer','status_check')
    or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 8 and 160 then
    raise exception 'Invalid drawer hardware command intent' using errcode='22023';
  end if;
  select * into v_device from public.mme_pos_register_devices where id=p_device_id for update;
  if not found or v_device.status not in ('online','pending') then
    raise exception 'Drawer device is not available for a command request' using errcode='55000';
  end if;
  if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.command',v_device.location_id) then
    raise exception 'Hardware command permission denied' using errcode='42501';
  end if;
  if p_command_type='open_drawer' and v_device.device_type<>'cash_drawer' then
    raise exception 'Open drawer intent requires a cash drawer device' using errcode='22023';
  end if;
  if p_drawer_session_id is not null and not exists(
    select 1 from public.mme_pos_cash_drawer_sessions s
    where s.id=p_drawer_session_id and s.register_reference=v_device.register_reference and s.status='open'
  ) then raise exception 'Open drawer session does not match the register' using errcode='23514'; end if;
  insert into public.mme_pos_drawer_hardware_commands(
    device_id,drawer_session_id,requested_by_person_id,command_type,idempotency_key
  ) values(p_device_id,p_drawer_session_id,p_actor_person_id,p_command_type,btrim(p_idempotency_key))
  on conflict(idempotency_key) do nothing returning id into v_id;
  if v_id is not null then return v_id; end if;
  select * into v_existing from public.mme_pos_drawer_hardware_commands c
    where c.idempotency_key=btrim(p_idempotency_key);
  if not found or v_existing.device_id<>p_device_id
    or v_existing.drawer_session_id is distinct from p_drawer_session_id
    or v_existing.requested_by_person_id<>p_actor_person_id
    or v_existing.command_type<>p_command_type then
    raise exception 'Idempotency key is already bound to a different command' using errcode='23505';
  end if;
  return v_existing.id;
end;
$$;

create or replace function public.mme_pos_claim_hardware_commands(
  p_limit integer default 10,p_lease_seconds integer default 45
) returns table(
  command_id uuid,device_id uuid,provider text,device_reference text,
  command_type text,idempotency_key text,lease_token uuid,attempt_count integer
)
language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
  if p_limit not between 1 and 50 or p_lease_seconds not between 10 and 300 then
    raise exception 'Invalid command claim parameters' using errcode='22023';
  end if;
  return query
  with candidates as (
    select c.id from public.mme_pos_drawer_hardware_commands c
    where c.status='requested' and c.next_attempt_at<=now()
      and (c.dispatch_lease_until is null or c.dispatch_lease_until<now())
      and c.dispatch_attempt_count<c.dispatch_max_attempts
    order by c.requested_at
    for update skip locked
    limit p_limit
  ), claimed as (
    update public.mme_pos_drawer_hardware_commands c
    set dispatch_lease_token=gen_random_uuid(),
        dispatch_lease_until=now()+make_interval(secs=>p_lease_seconds),
        dispatch_attempt_count=c.dispatch_attempt_count+1,
        dispatched_at=now()
    from candidates x where c.id=x.id
    returning c.id,c.device_id,c.command_type,c.idempotency_key,c.dispatch_lease_token,c.dispatch_attempt_count
  )
  select x.id,x.device_id,d.provider,d.device_reference,x.command_type,
    x.idempotency_key,x.dispatch_lease_token,x.dispatch_attempt_count
  from claimed x join public.mme_pos_register_devices d on d.id=x.device_id;
end;
$$;

create or replace function public.mme_pos_finish_hardware_command_delivery(
  p_command_id uuid,p_lease_token uuid,p_provider_accepted boolean,
  p_provider_command_id text default null,p_failure_code text default null,
  p_failure_detail text default null,p_retry_seconds integer default 30
) returns text
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_status text;
begin
  if p_command_id is null or p_lease_token is null or p_provider_accepted is null
    or p_retry_seconds not between 1 and 3600
    or (p_provider_command_id is not null and length(p_provider_command_id)>160) then
    raise exception 'Invalid hardware command delivery result' using errcode='22023';
  end if;
  update public.mme_pos_drawer_hardware_commands c
  set status=case when p_provider_accepted then 'acknowledged'
      when c.dispatch_attempt_count>=c.dispatch_max_attempts then 'failed' else 'requested' end,
      acknowledged_at=case when p_provider_accepted then now() else c.acknowledged_at end,
      completed_at=case when not p_provider_accepted and c.dispatch_attempt_count>=c.dispatch_max_attempts then now() else c.completed_at end,
      provider_command_id=case when p_provider_accepted then p_provider_command_id else c.provider_command_id end,
      failure_code=case when not p_provider_accepted then left(coalesce(p_failure_code,'PROVIDER_DELIVERY_FAILED'),80) else null end,
      failure_detail=case when not p_provider_accepted then left(coalesce(p_failure_detail,'Provider did not accept command'),300) else null end,
      next_attempt_at=case when not p_provider_accepted and c.dispatch_attempt_count<c.dispatch_max_attempts then now()+make_interval(secs=>p_retry_seconds) else c.next_attempt_at end,
      dispatch_lease_token=null,dispatch_lease_until=null
  where c.id=p_command_id and c.status='requested' and c.dispatch_lease_token=p_lease_token
  returning c.status into v_status;
  if not found then raise exception 'Command lease is missing, expired or no longer active' using errcode='55000'; end if;
  return v_status;
end;
$$;

revoke all on function public.mme_pos_claim_hardware_commands(integer,integer) from public,anon,authenticated;
revoke all on function public.mme_pos_finish_hardware_command_delivery(uuid,uuid,boolean,text,text,text,integer) from public,anon,authenticated;
grant execute on function public.mme_pos_claim_hardware_commands(integer,integer) to service_role;
grant execute on function public.mme_pos_finish_hardware_command_delivery(uuid,uuid,boolean,text,text,text,integer) to service_role;
comment on function public.mme_pos_claim_hardware_commands(integer,integer) is 'Atomically leases pending POS hardware commands to a trusted server worker; no physical transport is implied.';
commit;
