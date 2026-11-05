-- Build 009.15: POS drawer hardware registry, telemetry, command-intent history and IT incident queue.
-- This records intent and device-reported events only; it does not send commands to physical hardware.
begin;

create table public.mme_pos_register_devices (
  id uuid primary key default gen_random_uuid(),
  register_reference text not null check(length(btrim(register_reference)) between 1 and 80),
  device_reference text not null check(length(btrim(device_reference)) between 1 and 120),
  device_type text not null check(device_type in ('cash_drawer','receipt_printer','payment_terminal','register_controller')),
  provider text not null check(length(btrim(provider)) between 1 and 80),
  location_id uuid not null,
  status text not null default 'pending' check(status in ('pending','online','offline','maintenance','retired')),
  last_seen_at timestamptz,
  last_event_at timestamptz,
  registered_by_person_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider,device_reference)
);
create index mme_pos_register_devices_register_idx
  on public.mme_pos_register_devices(register_reference,status);

create table public.mme_pos_drawer_hardware_events (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
  provider_event_id text not null,
  event_type text not null check(event_type in (
    'heartbeat','device_online','device_offline','drawer_open_confirmed','drawer_open_failed',
    'drawer_closed_confirmed','connection_lost','connection_restored'
  )),
  drawer_session_id uuid references public.mme_pos_cash_drawer_sessions(id) on delete restrict,
  command_attempt_id uuid,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  safe_detail text,
  unique(device_id,provider_event_id)
);
create index mme_pos_drawer_hw_events_device_idx
  on public.mme_pos_drawer_hardware_events(device_id,received_at desc);

create table public.mme_pos_drawer_hardware_commands (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
  drawer_session_id uuid references public.mme_pos_cash_drawer_sessions(id) on delete restrict,
  requested_by_person_id uuid not null,
  command_type text not null check(command_type in ('open_drawer','status_check')),
  status text not null default 'requested' check(status in ('requested','acknowledged','confirmed','failed','timed_out','cancelled')),
  idempotency_key text not null unique,
  requested_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  completed_at timestamptz,
  failure_code text,
  failure_detail text,
  unique(id,device_id),
  check ((status in ('requested','acknowledged') and completed_at is null)
      or (status in ('confirmed','failed','timed_out','cancelled') and completed_at is not null))
);
create index mme_pos_drawer_hw_commands_pending_idx
  on public.mme_pos_drawer_hardware_commands(status,requested_at)
  where status in ('requested','acknowledged');
alter table public.mme_pos_drawer_hardware_events
  add constraint mme_pos_drawer_hw_event_command_fk foreign key(command_attempt_id,device_id)
  references public.mme_pos_drawer_hardware_commands(id,device_id) on delete restrict;

create table public.mme_pos_drawer_it_incidents (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
  drawer_session_id uuid references public.mme_pos_cash_drawer_sessions(id) on delete restrict,
  command_attempt_id uuid references public.mme_pos_drawer_hardware_commands(id) on delete restrict,
  source_event_id uuid references public.mme_pos_drawer_hardware_events(id) on delete restrict,
  incident_type text not null check(incident_type in ('drawer_open_failed','device_offline','connection_lost','sale_drawer_failure')),
  severity text not null default 'high' check(severity in ('medium','high','critical')),
  status text not null default 'open' check(status in ('open','acknowledged','in_progress','resolved','closed')),
  title text not null,
  description text not null,
  assigned_to_person_id uuid,
  acknowledged_by_person_id uuid,
  acknowledged_at timestamptz,
  resolution_note text,
  resolved_by_person_id uuid,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index mme_pos_drawer_it_incident_event_once
  on public.mme_pos_drawer_it_incidents(source_event_id,incident_type)
  where source_event_id is not null;
create index mme_pos_drawer_it_incident_queue_idx
  on public.mme_pos_drawer_it_incidents(status,severity,created_at desc);

alter table public.mme_pos_register_devices enable row level security;
alter table public.mme_pos_drawer_hardware_events enable row level security;
alter table public.mme_pos_drawer_hardware_commands enable row level security;
alter table public.mme_pos_drawer_it_incidents enable row level security;
revoke all on public.mme_pos_register_devices,public.mme_pos_drawer_hardware_events,
  public.mme_pos_drawer_hardware_commands,public.mme_pos_drawer_it_incidents from public,anon,authenticated;
grant all on public.mme_pos_register_devices,public.mme_pos_drawer_hardware_events,
  public.mme_pos_drawer_hardware_commands,public.mme_pos_drawer_it_incidents to service_role;

create or replace function public.mme_pos_authorize_hardware_action(
  p_actor_person_id uuid,p_permission_key text,p_location_id uuid
) returns boolean
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_person_status text; v_ceo_person_id uuid; v_frozen boolean; v_employment_status text;
begin
  if p_actor_person_id is null or p_location_id is null or p_permission_key not in (
    'pos.hardware.register','pos.hardware.command','pos.hardware.incident.view',
    'pos.hardware.incident.acknowledge','pos.hardware.incident.resolve'
  ) then return false; end if;
  select lifecycle_status into v_person_status from public.mme_person_identities where person_id=p_actor_person_id;
  if not found or v_person_status is distinct from 'active' then return false; end if;
  select ceo_person_id,employee_access_frozen into v_ceo_person_id,v_frozen
    from public.employee_security_settings where singleton=true;
  if not found or v_frozen is distinct from false or v_ceo_person_id is null then return false; end if;
  select employment_status into v_employment_status from public.employee_relationships where person_id=p_actor_person_id;
  if v_employment_status is distinct from 'active' then return false; end if;
  if p_actor_person_id=v_ceo_person_id then return true; end if;
  return exists(select 1 from public.employee_permission_grants g
    where g.person_id=p_actor_person_id and g.permission_key=p_permission_key
      and g.revoked_at is null and (g.expires_at is null or g.expires_at>now())
      and (g.scope='{}'::jsonb or g.scope->>'location_id'=p_location_id::text));
end;
$$;

create or replace function public.mme_pos_register_drawer_hardware_device(
  p_register_reference text,p_device_reference text,p_device_type text,p_provider text,
  p_location_id uuid,p_actor_person_id uuid
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_id uuid;
begin
  if p_register_reference is null or length(btrim(p_register_reference)) not between 1 and 80
    or p_device_reference is null or length(btrim(p_device_reference)) not between 1 and 120
    or p_device_type not in ('cash_drawer','receipt_printer','payment_terminal','register_controller')
    or p_provider is null or length(btrim(p_provider)) not between 1 and 80
    or p_location_id is null or p_actor_person_id is null then
    raise exception 'Invalid POS hardware registration' using errcode='22023';
  end if;
  if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.register',p_location_id) then
    raise exception 'Hardware registration permission denied' using errcode='42501';
  end if;
  insert into public.mme_pos_register_devices(
    register_reference,device_reference,device_type,provider,location_id,registered_by_person_id
  ) values(btrim(p_register_reference),btrim(p_device_reference),p_device_type,btrim(p_provider),p_location_id,p_actor_person_id)
  returning id into v_id;
  return v_id;
end;
$;

create or replace function public.mme_pos_record_drawer_hardware_command_intent(
  p_device_id uuid,p_drawer_session_id uuid,p_actor_person_id uuid,
  p_command_type text,p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device public.mme_pos_register_devices%rowtype; v_id uuid;
begin
  if p_device_id is null or p_actor_person_id is null
    or p_command_type not in ('open_drawer','status_check')
    or p_idempotency_key is null or length(btrim(p_idempotency_key))<8 then
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
  ) values(p_device_id,p_drawer_session_id,p_actor_person_id,p_command_type,p_idempotency_key)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.mme_pos_ingest_drawer_hardware_event(
  p_device_id uuid,p_provider_event_id text,p_event_type text,p_occurred_at timestamptz,
  p_command_attempt_id uuid default null,p_safe_detail text default null
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device public.mme_pos_register_devices%rowtype; v_event_id uuid; v_event public.mme_pos_drawer_hardware_events%rowtype;
  v_session_id uuid; v_incident_type text; v_title text; v_description text; v_status text; v_command_type text;
begin
  if p_device_id is null or p_provider_event_id is null or length(btrim(p_provider_event_id)) not between 1 and 160
    or p_event_type not in ('heartbeat','device_online','device_offline','drawer_open_confirmed','drawer_open_failed',
      'drawer_closed_confirmed','connection_lost','connection_restored') or p_occurred_at is null then
    raise exception 'Invalid drawer hardware event' using errcode='22023';
  end if;
  select * into v_device from public.mme_pos_register_devices where id=p_device_id for update;
  if not found or v_device.status='retired' then raise exception 'Registered active device not found' using errcode='P0002'; end if;
  select id into v_event_id from public.mme_pos_drawer_hardware_events
    where device_id=p_device_id and provider_event_id=p_provider_event_id;
  if v_event_id is not null then return v_event_id; end if;
  if p_command_attempt_id is not null and not exists(
    select 1 from public.mme_pos_drawer_hardware_commands c where c.id=p_command_attempt_id and c.device_id=p_device_id
  ) then raise exception 'Command attempt does not belong to this device' using errcode='23514'; end if;
  select id into v_session_id from public.mme_pos_cash_drawer_sessions
    where register_reference=v_device.register_reference and status='open'
    order by opened_at desc limit 1;
  insert into public.mme_pos_drawer_hardware_events(
    device_id,provider_event_id,event_type,drawer_session_id,command_attempt_id,occurred_at,safe_detail
  ) values(p_device_id,p_provider_event_id,p_event_type,v_session_id,p_command_attempt_id,p_occurred_at,left(p_safe_detail,300))
  returning id into v_event_id;

  v_status:=case when p_event_type in ('device_offline','connection_lost') then 'offline'
    when p_event_type in ('device_online','connection_restored','heartbeat') then 'online'
    else v_device.status end;
  update public.mme_pos_register_devices set status=v_status,last_seen_at=now(),last_event_at=p_occurred_at,updated_at=now()
    where id=p_device_id;

  if p_command_attempt_id is not null then
    update public.mme_pos_drawer_hardware_commands set
      status=case when p_event_type='drawer_open_confirmed' then 'confirmed'
        when p_event_type='drawer_open_failed' then 'failed'
        when p_event_type in ('device_offline','connection_lost') then 'failed'
        when p_event_type='heartbeat' or p_event_type='device_online' then status
        else status end,
      acknowledged_at=coalesce(acknowledged_at,now()),
      completed_at=case when p_event_type in ('drawer_open_confirmed','drawer_open_failed','device_offline','connection_lost') then now() else completed_at end,
      failure_code=case when p_event_type='drawer_open_failed' then 'DRAWER_OPEN_FAILED'
        when p_event_type in ('device_offline','connection_lost') then 'DEVICE_UNAVAILABLE' else failure_code end,
      failure_detail=case when p_event_type in ('drawer_open_failed','device_offline','connection_lost') then left(p_safe_detail,300) else failure_detail end
    where id=p_command_attempt_id and status in ('requested','acknowledged');
  end if;

  if p_command_attempt_id is not null then
    select command_type into v_command_type from public.mme_pos_drawer_hardware_commands where id=p_command_attempt_id;
  end if;
  v_incident_type:=case
    when p_event_type='drawer_open_failed' and v_command_type='open_drawer'
      and v_session_id is not null and exists(
        select 1 from public.mme_pos_cash_drawer_movements m
        where m.drawer_session_id=v_session_id and m.movement_type='cash_sale'
      ) then 'sale_drawer_failure'
    when p_event_type='drawer_open_failed' then 'drawer_open_failed'
    when p_event_type='device_offline' then 'device_offline'
    when p_event_type='connection_lost' then 'connection_lost' end;
  if v_incident_type is not null then
    v_title:=case v_incident_type when 'drawer_open_failed' then 'Cash drawer failed to open'
      when 'sale_drawer_failure' then 'Sale completed but cash drawer failed to open'
      when 'device_offline' then 'POS device offline' else 'POS device connection lost' end;
    v_description:=left(coalesce(p_safe_detail,'Device reported a hardware failure')||' Register: '||v_device.register_reference,500);
    insert into public.mme_pos_drawer_it_incidents(
      device_id,drawer_session_id,command_attempt_id,source_event_id,incident_type,severity,title,description
    ) values(p_device_id,v_session_id,p_command_attempt_id,v_event_id,v_incident_type,'high',v_title,v_description)
    on conflict(source_event_id,incident_type) where source_event_id is not null do nothing;
  end if;
  return v_event_id;
end;
$$;

create or replace function public.mme_pos_update_drawer_it_incident(
  p_incident_id uuid,p_actor_person_id uuid,p_action text,p_note text default null
) returns text
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_incident public.mme_pos_drawer_it_incidents%rowtype; v_permission text;
begin
  if p_incident_id is null or p_actor_person_id is null or p_action not in ('acknowledge','start','resolve','close') then
    raise exception 'Invalid IT incident update' using errcode='22023';
  end if;
  select * into v_incident from public.mme_pos_drawer_it_incidents where id=p_incident_id for update;
  if not found then raise exception 'IT incident not found' using errcode='P0002'; end if;
  v_permission:=case when p_action='resolve' or p_action='close' then 'pos.hardware.incident.resolve' else 'pos.hardware.incident.acknowledge' end;
  if not public.mme_pos_authorize_hardware_action(p_actor_person_id,v_permission,
    (select location_id from public.mme_pos_register_devices where id=v_incident.device_id)) then
    raise exception 'IT incident permission denied' using errcode='42501';
  end if;
  if p_action='acknowledge' then
    if v_incident.status<>'open' then raise exception 'Only open incidents can be acknowledged' using errcode='23514'; end if;
    update public.mme_pos_drawer_it_incidents set status='acknowledged',acknowledged_by_person_id=p_actor_person_id,
      acknowledged_at=now(),updated_at=now() where id=p_incident_id;
  elsif p_action='start' then
    if v_incident.status not in ('open','acknowledged') then raise exception 'Incident cannot enter in-progress state' using errcode='23514'; end if;
    update public.mme_pos_drawer_it_incidents set status='in_progress',assigned_to_person_id=coalesce(assigned_to_person_id,p_actor_person_id),
      updated_at=now() where id=p_incident_id;
  elsif p_action='resolve' then
    if v_incident.status not in ('open','acknowledged','in_progress') or length(btrim(coalesce(p_note,'')))<8 then
      raise exception 'Resolution requires an active incident and a meaningful note' using errcode='23514';
    end if;
    update public.mme_pos_drawer_it_incidents set status='resolved',resolution_note=left(p_note,1000),
      resolved_by_person_id=p_actor_person_id,resolved_at=now(),updated_at=now() where id=p_incident_id;
  else
    if v_incident.status<>'resolved' then raise exception 'Only resolved incidents can be closed' using errcode='23514'; end if;
    update public.mme_pos_drawer_it_incidents set status='closed',updated_at=now() where id=p_incident_id;
  end if;
  return case when p_action='start' then 'in_progress' when p_action='acknowledge' then 'acknowledged'
    when p_action='resolve' then 'resolved' else 'closed' end;
end;
$$;

revoke all on function public.mme_pos_authorize_hardware_action(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_register_drawer_hardware_device(text,text,text,text,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_record_drawer_hardware_command_intent(uuid,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_ingest_drawer_hardware_event(uuid,text,text,timestamptz,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_update_drawer_it_incident(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_authorize_hardware_action(uuid,text,uuid) to service_role;
grant execute on function public.mme_pos_register_drawer_hardware_device(text,text,text,text,uuid,uuid) to service_role;
grant execute on function public.mme_pos_record_drawer_hardware_command_intent(uuid,uuid,uuid,text,text) to service_role;
grant execute on function public.mme_pos_ingest_drawer_hardware_event(uuid,text,text,timestamptz,uuid,text) to service_role;
grant execute on function public.mme_pos_update_drawer_it_incident(uuid,uuid,text,text) to service_role;

comment on table public.mme_pos_register_devices is 'Register hardware registry and last-known health; no device secrets are stored.';
comment on table public.mme_pos_drawer_hardware_commands is 'Auditable command intent and provider-reported outcome; not a hardware command transport.';
comment on table public.mme_pos_drawer_it_incidents is 'IT incident queue for drawer failures and POS device connectivity faults.';
commit;
