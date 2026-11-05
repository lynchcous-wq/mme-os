-- Build 009.16: secure provider references, one-time pairing, heartbeat supervision and offline escalation.
-- Raw provider credentials and pairing secrets are never stored here. A trusted backend validates provider proofs.
begin;

alter table public.mme_pos_register_devices
  add column if not exists paired_at timestamptz,
  add column if not exists last_heartbeat_at timestamptz,
  add column if not exists heartbeat_interval_seconds integer not null default 60
    check(heartbeat_interval_seconds between 15 and 3600);

create table public.mme_pos_hardware_provider_adapters (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null,
  adapter_version text not null,
  credential_secret_ref text,
  webhook_secret_ref text,
  capabilities jsonb not null default '[]'::jsonb
    check(jsonb_typeof(capabilities)='array'),
  enabled boolean not null default false,
  created_by_person_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider_code,adapter_version),
  check(credential_secret_ref is null or credential_secret_ref !~* '(password|secret|token)=[^/]+'),
  check(webhook_secret_ref is null or webhook_secret_ref !~* '(password|secret|token)=[^/]+')
);
create table public.mme_pos_hardware_pairing_challenges (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
  challenge_digest text not null check(challenge_digest ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  created_by_person_id uuid not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(device_id,challenge_digest)
);
create index mme_pos_hardware_pairing_expiry_idx
  on public.mme_pos_hardware_pairing_challenges(expires_at)
  where consumed_at is null;

alter table public.mme_pos_hardware_provider_adapters enable row level security;
alter table public.mme_pos_hardware_pairing_challenges enable row level security;
revoke all on public.mme_pos_hardware_provider_adapters,public.mme_pos_hardware_pairing_challenges
  from public,anon,authenticated;
grant all on public.mme_pos_hardware_provider_adapters,public.mme_pos_hardware_pairing_challenges to service_role;

create unique index mme_pos_hardware_active_incident_once
  on public.mme_pos_drawer_it_incidents(device_id,incident_type)
  where status in ('open','acknowledged','in_progress');

create or replace function public.mme_pos_create_hardware_pairing_challenge(
  p_device_id uuid,p_actor_person_id uuid,p_challenge_digest text,p_expires_at timestamptz
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device public.mme_pos_register_devices%rowtype; v_id uuid;
begin
  if p_device_id is null or p_actor_person_id is null or p_challenge_digest is null
    or p_challenge_digest !~ '^[a-f0-9]{64}$'
    or p_expires_at is null or p_expires_at<=now() or p_expires_at>now()+interval '15 minutes' then
    raise exception 'Invalid hardware pairing challenge' using errcode='22023';
  end if;
  select * into v_device from public.mme_pos_register_devices where id=p_device_id for update;
  if not found or v_device.status='retired' then
    raise exception 'Device is not eligible for pairing' using errcode='55000';
  end if;
  if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.register',v_device.location_id) then
    raise exception 'Hardware pairing permission denied' using errcode='42501';
  end if;
  insert into public.mme_pos_hardware_pairing_challenges(device_id,challenge_digest,expires_at,created_by_person_id)
  values(p_device_id,p_challenge_digest,p_expires_at,p_actor_person_id) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.mme_pos_complete_hardware_pairing(
  p_device_id uuid,p_challenge_digest text,p_provider_proof_verified boolean
) returns boolean
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_challenge public.mme_pos_hardware_pairing_challenges%rowtype;
begin
  if p_device_id is null or p_challenge_digest !~ '^[a-f0-9]{64}$'
    or p_provider_proof_verified is distinct from true then
    raise exception 'Hardware provider proof was not verified by the trusted adapter' using errcode='42501';
  end if;
  select * into v_challenge from public.mme_pos_hardware_pairing_challenges
    where device_id=p_device_id and challenge_digest=p_challenge_digest
      and consumed_at is null and expires_at>now()
    for update;
  if not found then raise exception 'Pairing challenge is invalid, expired or already consumed' using errcode='28000'; end if;
  update public.mme_pos_hardware_pairing_challenges set consumed_at=now() where id=v_challenge.id;
  update public.mme_pos_register_devices set paired_at=now(),status='online',last_seen_at=now(),
    last_heartbeat_at=now(),updated_at=now() where id=p_device_id and status<>'retired';
  return found;
end;
$$;

create or replace function public.mme_pos_sweep_stale_hardware_devices(
  p_now timestamptz default now(),p_max_stale_seconds integer default 300
) returns integer
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device record; v_count integer:=0;
begin
  if p_now is null or p_max_stale_seconds not between 60 and 86400 then
    raise exception 'Invalid heartbeat sweep parameters' using errcode='22023';
  end if;
  for v_device in
    select d.* from public.mme_pos_register_devices d
    where d.status='online' and d.paired_at is not null
      and coalesce(d.last_heartbeat_at,d.last_seen_at)<p_now-make_interval(secs=>greatest(d.heartbeat_interval_seconds*3,p_max_stale_seconds))
    for update
  loop
    update public.mme_pos_register_devices set status='offline',updated_at=p_now where id=v_device.id;
    insert into public.mme_pos_drawer_it_incidents(
      device_id,incident_type,severity,title,description
    ) values(v_device.id,'device_offline','high','POS device heartbeat missed',
      left('No heartbeat received within configured threshold. Register: '||v_device.register_reference,500))
    on conflict(device_id,incident_type) where status in ('open','acknowledged','in_progress') do nothing;
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.mme_pos_record_hardware_heartbeat(
  p_device_id uuid,p_provider_event_id text,p_occurred_at timestamptz
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_event_id uuid; v_device_status text;
begin
  if p_device_id is null or p_provider_event_id is null
    or length(btrim(p_provider_event_id)) not between 1 and 160
    or p_occurred_at is null
    or p_occurred_at<now()-interval '5 minutes'
    or p_occurred_at>now()+interval '60 seconds' then
    raise exception 'Invalid or out-of-window hardware heartbeat' using errcode='22023';
  end if;
  select status into v_device_status from public.mme_pos_register_devices
    where id=p_device_id for update;
  if not found or v_device_status='retired' then
    raise exception 'Registered active device not found' using errcode='P0002';
  end if;
  select id into v_event_id from public.mme_pos_drawer_hardware_events
    where device_id=p_device_id and provider_event_id=p_provider_event_id;
  if v_event_id is not null then return v_event_id; end if;
  v_event_id:=public.mme_pos_ingest_drawer_hardware_event(
    p_device_id,p_provider_event_id,'heartbeat',p_occurred_at,null,'Provider heartbeat'
  );
  update public.mme_pos_register_devices set last_heartbeat_at=greatest(coalesce(last_heartbeat_at,p_occurred_at),p_occurred_at),
    status='online',paired_at=coalesce(paired_at,now()),last_seen_at=now(),updated_at=now()
    where id=p_device_id and status<>'retired';
  return v_event_id;
end;
$$;

revoke all on function public.mme_pos_create_hardware_pairing_challenge(uuid,uuid,text,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_pos_complete_hardware_pairing(uuid,text,boolean) from public,anon,authenticated;
revoke all on function public.mme_pos_sweep_stale_hardware_devices(timestamptz,integer) from public,anon,authenticated;
revoke all on function public.mme_pos_record_hardware_heartbeat(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.mme_pos_create_hardware_pairing_challenge(uuid,uuid,text,timestamptz) to service_role;
grant execute on function public.mme_pos_complete_hardware_pairing(uuid,text,boolean) to service_role;
grant execute on function public.mme_pos_sweep_stale_hardware_devices(timestamptz,integer) to service_role;
grant execute on function public.mme_pos_record_hardware_heartbeat(uuid,text,timestamptz) to service_role;

comment on table public.mme_pos_hardware_provider_adapters is 'Provider adapter metadata and external secret references only; never store raw credentials.';
comment on table public.mme_pos_hardware_pairing_challenges is 'Short-lived one-time challenge digests; provider proof must be verified by a trusted backend before completion.';
comment on function public.mme_pos_complete_hardware_pairing(uuid,text,boolean) is 'Service-role only; caller must set provider proof verified only after cryptographic validation outside the database.';
comment on function public.mme_pos_sweep_stale_hardware_devices(timestamptz,integer) is 'Scheduled service-role sweep for missed device heartbeats and IT incident escalation.';
commit;
