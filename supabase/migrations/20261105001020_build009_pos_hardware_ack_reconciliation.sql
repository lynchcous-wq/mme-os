-- Build 009.21: durable, idempotent POS hardware acknowledgments and command-state reconciliation.
begin;

create table public.mme_pos_hardware_acknowledgments (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
  provider_event_id text not null check(length(btrim(provider_event_id)) between 1 and 160),
  event_type text not null check(event_type in ('drawer_open_confirmed','drawer_open_failed')),
  command_id uuid references public.mme_pos_drawer_hardware_commands(id) on delete restrict,
  provider_command_id text check(provider_command_id is null or length(provider_command_id)<=160),
  reconciliation_state text not null default 'unmatched'
    check(reconciliation_state in ('unmatched','matched_confirmed','matched_failed','conflict')),
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  reconciled_at timestamptz,
  safe_detail text check(safe_detail is null or length(safe_detail)<=300),
  unique(device_id,provider_event_id)
);
create index mme_pos_hw_ack_unmatched_idx
  on public.mme_pos_hardware_acknowledgments(device_id,received_at)
  where reconciliation_state='unmatched';
create index mme_pos_hw_ack_command_idx
  on public.mme_pos_hardware_acknowledgments(command_id,occurred_at desc)
  where command_id is not null;

alter table public.mme_pos_hardware_acknowledgments enable row level security;
revoke all on public.mme_pos_hardware_acknowledgments from public,anon,authenticated;
grant all on public.mme_pos_hardware_acknowledgments to service_role;

create or replace function public.mme_pos_apply_hardware_acknowledgment(p_acknowledgment_id uuid)
returns text
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
  v_ack public.mme_pos_hardware_acknowledgments%rowtype;
  v_command public.mme_pos_drawer_hardware_commands%rowtype;
  v_found boolean := false;
  v_candidates integer := 0;
  v_state text;
begin
  select * into v_ack from public.mme_pos_hardware_acknowledgments
    where id=p_acknowledgment_id for update;
  if not found then raise exception 'Hardware acknowledgment not found' using errcode='P0002'; end if;
  if v_ack.reconciliation_state<>'unmatched' then return v_ack.reconciliation_state; end if;

  if v_ack.command_id is not null then
    select * into v_command from public.mme_pos_drawer_hardware_commands
      where id=v_ack.command_id and device_id=v_ack.device_id for update;
    v_found:=found;
  elsif v_ack.provider_command_id is not null then
    select count(*) into v_candidates from public.mme_pos_drawer_hardware_commands
      where device_id=v_ack.device_id and provider_command_id=v_ack.provider_command_id;
    if v_candidates>1 then
      update public.mme_pos_hardware_acknowledgments set reconciliation_state='conflict',
        reconciliation_detail='Provider command identifier matched multiple commands for this device.',
        reconciled_at=now() where id=v_ack.id;
      return 'conflict';
    elsif v_candidates=1 then
      select * into v_command from public.mme_pos_drawer_hardware_commands
        where device_id=v_ack.device_id and provider_command_id=v_ack.provider_command_id for update;
      v_found:=found;
    end if;
  end if;

  if not v_found then return 'unmatched'; end if;
  if v_command.command_type<>'open_drawer' then
    update public.mme_pos_hardware_acknowledgments set reconciliation_state='conflict',
      command_id=v_command.id,reconciled_at=now() where id=v_ack.id;
    return 'conflict';
  end if;

  if v_command.status in ('confirmed','failed','cancelled') then
    if (v_command.status='confirmed' and v_ack.event_type='drawer_open_confirmed')
      or (v_command.status='failed' and v_ack.event_type='drawer_open_failed') then
      v_state:=case when v_command.status='confirmed' then 'matched_confirmed' else 'matched_failed' end;
      update public.mme_pos_hardware_acknowledgments set reconciliation_state=v_state,
        command_id=v_command.id,reconciled_at=now() where id=v_ack.id;
      return v_state;
    end if;
    update public.mme_pos_hardware_acknowledgments set reconciliation_state='conflict',
      command_id=v_command.id,reconciled_at=now() where id=v_ack.id;
    return 'conflict';
  end if;

  if v_command.status not in ('requested','acknowledged','timed_out') then
    return 'unmatched';
  end if;

  if v_ack.event_type='drawer_open_confirmed' then
    update public.mme_pos_drawer_hardware_commands set status='confirmed',
      acknowledged_at=coalesce(acknowledged_at,now()),completed_at=coalesce(completed_at,now()),
      failure_code=null,failure_detail=null,dispatch_lease_token=null,dispatch_lease_until=null,
      delivery_uncertain=false,reconciliation_required=false,
      delivery_uncertain_at=null,delivery_uncertain_reason=null
    where id=v_command.id;
    v_state:='matched_confirmed';
  else
    update public.mme_pos_drawer_hardware_commands set status='failed',
      acknowledged_at=coalesce(acknowledged_at,now()),completed_at=coalesce(completed_at,now()),
      failure_code='DRAWER_OPEN_FAILED',
      failure_detail=coalesce(v_ack.safe_detail,'Provider confirmed drawer-open failure.'),
      dispatch_lease_token=null,dispatch_lease_until=null,
      delivery_uncertain=false,reconciliation_required=false,
      delivery_uncertain_at=null,delivery_uncertain_reason=null
    where id=v_command.id;
    v_state:='matched_failed';
  end if;

  update public.mme_pos_hardware_acknowledgments set reconciliation_state=v_state,
    command_id=v_command.id,reconciled_at=now() where id=v_ack.id;
  return v_state;
end;
$$;

create or replace function public.mme_pos_ingest_hardware_acknowledgment(
  p_device_id uuid,p_provider_event_id text,p_event_type text,p_occurred_at timestamptz,
  p_command_id uuid default null,p_provider_command_id text default null,p_safe_detail text default null
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_ack public.mme_pos_hardware_acknowledgments%rowtype; v_state text;
begin
  if p_device_id is null or p_provider_event_id is null
    or length(btrim(p_provider_event_id)) not between 1 and 160
    or p_event_type is null or p_event_type not in ('drawer_open_confirmed','drawer_open_failed')
    or p_occurred_at is null
    or (p_provider_command_id is not null and length(p_provider_command_id)>160)
    then
    raise exception 'Invalid hardware acknowledgment' using errcode='22023';
  end if;
  if not exists(select 1 from public.mme_pos_register_devices d
    where d.id=p_device_id and d.status<>'retired') then
    raise exception 'Registered hardware device not found' using errcode='P0002';
  end if;
  insert into public.mme_pos_hardware_acknowledgments(
    device_id,provider_event_id,event_type,command_id,provider_command_id,occurred_at,safe_detail
  ) values(p_device_id,btrim(p_provider_event_id),p_event_type,p_command_id,
    nullif(btrim(p_provider_command_id),''),p_occurred_at,left(p_safe_detail,300))
  on conflict(device_id,provider_event_id) do nothing;

  select * into v_ack from public.mme_pos_hardware_acknowledgments
    where device_id=p_device_id and provider_event_id=btrim(p_provider_event_id);
  if v_ack.event_type<>p_event_type
    or v_ack.occurred_at is distinct from p_occurred_at
    or v_ack.command_id is distinct from p_command_id
    or v_ack.provider_command_id is distinct from nullif(btrim(p_provider_command_id),'') then
    raise exception 'Provider event identifier was reused with conflicting acknowledgment data' using errcode='23505';
  end if;
  v_state:=public.mme_pos_apply_hardware_acknowledgment(v_ack.id);
  return jsonb_build_object('acknowledgment_id',v_ack.id,'state',v_state,'command_id',v_ack.command_id);
end;
$$;

create or replace function public.mme_pos_reconcile_hardware_acknowledgments(
  p_device_id uuid,p_limit integer default 100
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_ack record; v_count integer:=0; v_matched integer:=0; v_conflict integer:=0;
begin
  if p_device_id is null or p_limit not between 1 and 500 then
    raise exception 'Invalid acknowledgment reconciliation request' using errcode='22023';
  end if;
  for v_ack in
    select id from public.mme_pos_hardware_acknowledgments
    where device_id=p_device_id and reconciliation_state='unmatched'
    order by received_at for update skip locked limit p_limit
  loop
    v_count:=v_count+1;
    case public.mme_pos_apply_hardware_acknowledgment(v_ack.id)
      when 'matched_confirmed' then v_matched:=v_matched+1;
      when 'matched_failed' then v_matched:=v_matched+1;
      when 'conflict' then v_conflict:=v_conflict+1;
      else null;
    end case;
  end loop;
  return jsonb_build_object('processed',v_count,'matched',v_matched,'conflicts',v_conflict);
end;
$$;

revoke all on function public.mme_pos_apply_hardware_acknowledgment(uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_ingest_hardware_acknowledgment(uuid,text,text,timestamptz,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_reconcile_hardware_acknowledgments(uuid,integer) from public,anon,authenticated;
grant execute on function public.mme_pos_ingest_hardware_acknowledgment(uuid,text,text,timestamptz,uuid,text,text) to service_role;
grant execute on function public.mme_pos_reconcile_hardware_acknowledgments(uuid,integer) to service_role;
comment on table public.mme_pos_hardware_acknowledgments is
  'Idempotent provider acknowledgment ledger; unmatched events remain pending until exact device-bound command correlation succeeds.';
commit;
