-- Build 009.25: POS network segmentation inventory, authenticated connection telemetry and certificate lifecycle.
-- This records intended network posture and trusted-agent observations; it does not configure switches/firewalls.
begin;

create table public.mme_pos_network_zones (
 id uuid primary key default gen_random_uuid(),
 zone_key text not null unique check(zone_key in ('pos','payment','peripherals','management','guest','infrastructure')),
 display_name text not null check(length(btrim(display_name)) between 2 and 100),
 trust_level text not null check(trust_level in ('restricted','high','standard','untrusted')),
 description text check(description is null or length(description)<=800),
 status text not null default 'planned' check(status in ('planned','active','restricted','retired')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.mme_pos_network_devices (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 zone_id uuid not null references public.mme_pos_network_zones(id) on delete restrict,
 network_identifier text check(network_identifier is null or length(network_identifier)<=120),
 ip_address inet,
 mac_address macaddr,
 vlan_reference text check(vlan_reference is null or length(vlan_reference)<=80),
 connection_type text not null check(connection_type in ('ethernet','wifi','usb_bridge','vendor_tunnel','unknown')),
 security_posture text not null default 'unknown' check(security_posture in ('unknown','compliant','noncompliant','quarantined')),
 last_verified_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(device_id)
);
create index mme_pos_network_devices_zone_idx on public.mme_pos_network_devices(zone_id,security_posture);

create table public.mme_pos_network_connections (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 zone_id uuid not null references public.mme_pos_network_zones(id) on delete restrict,
 connection_state text not null check(connection_state in ('connected','degraded','disconnected','blocked','unknown')),
 authenticated boolean not null default false,
 encrypted boolean not null default false,
 mutual_auth boolean not null default false,
 protocol text check(protocol is null or length(protocol)<=40),
 peer_identity text check(peer_identity is null or length(peer_identity)<=160),
 latency_ms integer check(latency_ms is null or latency_ms between 0 and 600000),
 packet_loss_percent numeric(5,2) check(packet_loss_percent is null or packet_loss_percent between 0 and 100),
 observed_at timestamptz not null,
 received_at timestamptz not null default now(),
 source text not null check(source in ('trusted_agent','network_monitor','provider_webhook','manual_verification')),
 safe_detail text check(safe_detail is null or length(safe_detail)<=800)
);
create index mme_pos_network_connections_device_time_idx on public.mme_pos_network_connections(device_id,observed_at desc);

create table public.mme_pos_device_certificates (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 certificate_fingerprint_sha256 text not null check(certificate_fingerprint_sha256 ~ '^[a-f0-9]{64}$'),
 issuer text not null check(length(btrim(issuer)) between 1 and 160),
 subject text not null check(length(btrim(subject)) between 1 and 240),
 serial_reference text check(serial_reference is null or length(serial_reference)<=160),
 secret_reference text not null check(length(btrim(secret_reference)) between 1 and 240),
 not_before timestamptz not null,
 expires_at timestamptz not null,
 status text not null default 'pending' check(status in ('pending','active','expiring','revoked','expired','superseded')),
 verified_by_person_id uuid,
 verified_at timestamptz,
 revoked_by_person_id uuid,
 revoked_at timestamptz,
 created_at timestamptz not null default now(),
 check(expires_at>not_before),
 check((status='active' and verified_by_person_id is not null and verified_at is not null and revoked_at is null)
    or status<>'active'),
 check((revoked_at is null and revoked_by_person_id is null) or (revoked_at is not null and revoked_by_person_id is not null))
);
create unique index mme_pos_device_cert_active_fingerprint
 on public.mme_pos_device_certificates(certificate_fingerprint_sha256) where status in ('pending','active','expiring');
create index mme_pos_device_cert_expiry_idx on public.mme_pos_device_certificates(status,expires_at);

create table public.mme_pos_network_health (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 zone_id uuid not null references public.mme_pos_network_zones(id) on delete restrict,
 availability_percent numeric(5,2) check(availability_percent is null or availability_percent between 0 and 100),
 latency_ms integer check(latency_ms is null or latency_ms between 0 and 600000),
 packet_loss_percent numeric(5,2) check(packet_loss_percent is null or packet_loss_percent between 0 and 100),
 jitter_ms integer check(jitter_ms is null or jitter_ms between 0 and 600000),
 bandwidth_mbps numeric(12,2) check(bandwidth_mbps is null or bandwidth_mbps>=0),
 certificate_days_remaining integer,
 health_state text not null check(health_state in ('healthy','degraded','critical','unknown')),
 observed_at timestamptz not null,
 received_at timestamptz not null default now(),
 source text not null check(source in ('trusted_agent','network_monitor','provider_webhook','manual_verification'))
);
create index mme_pos_network_health_device_time_idx on public.mme_pos_network_health(device_id,observed_at desc);

create table public.mme_pos_network_incidents (
 id uuid primary key default gen_random_uuid(),
 device_id uuid references public.mme_pos_register_devices(id) on delete restrict,
 zone_id uuid references public.mme_pos_network_zones(id) on delete restrict,
 incident_type text not null check(incident_type in ('connectivity_loss','encryption_missing','authentication_failure','certificate_expiring','certificate_revoked','segmentation_violation','packet_loss','latency','failover')),
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','acknowledged','investigating','mitigating','resolved','closed')),
 title text not null check(length(btrim(title)) between 3 and 160),
 safe_detail text check(safe_detail is null or length(safe_detail)<=1200),
 assigned_to_person_id uuid,
 acknowledged_by_person_id uuid,
 acknowledged_at timestamptz,
 resolution_note text check(resolution_note is null or length(resolution_note)<=1200),
 resolved_by_person_id uuid,
 resolved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_pos_network_incident_queue_idx on public.mme_pos_network_incidents(status,severity,created_at desc);

create table public.mme_pos_network_failover_events (
 id uuid primary key default gen_random_uuid(),
 device_id uuid references public.mme_pos_register_devices(id) on delete restrict,
 location_id uuid not null,
 source_path text not null check(length(btrim(source_path)) between 1 and 120),
 target_path text not null check(length(btrim(target_path)) between 1 and 120),
 failover_state text not null check(failover_state in ('requested','in_progress','completed','failed','reverted','manual_review')),
 reason text not null check(length(btrim(reason)) between 8 and 800),
 initiated_by_person_id uuid,
 observed_at timestamptz not null default now(),
 completed_at timestamptz,
 safe_result text check(safe_result is null or length(safe_result)<=1000),
 check(completed_at is null or completed_at>=observed_at)
);
create index mme_pos_network_failover_location_idx on public.mme_pos_network_failover_events(location_id,observed_at desc);

create table public.mme_pos_network_security_events (
 id uuid primary key default gen_random_uuid(),
 device_id uuid references public.mme_pos_register_devices(id) on delete restrict,
 zone_id uuid references public.mme_pos_network_zones(id) on delete restrict,
 event_type text not null check(event_type in ('unauthenticated_peer','unencrypted_session','certificate_mismatch','replay_suspected','zone_mismatch','unexpected_peer','credential_rotation','blocked_connection')),
 severity text not null check(severity in ('low','medium','high','critical')),
 source_reference text check(source_reference is null or length(source_reference)<=160),
 safe_detail text check(safe_detail is null or length(safe_detail)<=1200),
 occurred_at timestamptz not null,
 received_at timestamptz not null default now()
);
create index mme_pos_network_security_event_time_idx on public.mme_pos_network_security_events(occurred_at desc);

alter table public.mme_pos_network_zones enable row level security;
alter table public.mme_pos_network_devices enable row level security;
alter table public.mme_pos_network_connections enable row level security;
alter table public.mme_pos_device_certificates enable row level security;
alter table public.mme_pos_network_health enable row level security;
alter table public.mme_pos_network_incidents enable row level security;
alter table public.mme_pos_network_failover_events enable row level security;
alter table public.mme_pos_network_security_events enable row level security;
revoke all on public.mme_pos_network_zones,public.mme_pos_network_devices,public.mme_pos_network_connections,
 public.mme_pos_device_certificates,public.mme_pos_network_health,public.mme_pos_network_incidents,
 public.mme_pos_network_failover_events,public.mme_pos_network_security_events from public,anon,authenticated;
grant all on public.mme_pos_network_zones,public.mme_pos_network_devices,public.mme_pos_network_connections,
 public.mme_pos_device_certificates,public.mme_pos_network_health,public.mme_pos_network_incidents,
 public.mme_pos_network_failover_events,public.mme_pos_network_security_events to service_role;

create or replace function public.mme_pos_authorize_hardware_action(
 p_actor_person_id uuid,p_permission_key text,p_location_id uuid
) returns boolean
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_person_status text; v_ceo_person_id uuid; v_frozen boolean; v_employment_status text;
begin
 if p_actor_person_id is null or p_location_id is null or p_permission_key not in (
  'pos.hardware.register','pos.hardware.command','pos.hardware.incident.view',
  'pos.hardware.incident.acknowledge','pos.hardware.incident.resolve',
  'pos.hardware.admin','pos.hardware.assign','pos.hardware.configure',
  'pos.hardware.approve','pos.hardware.retire','pos.network.view',
  'pos.network.manage','pos.network.certificates','pos.network.incidents'
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

create or replace function public.mme_pos_register_network_device(
 p_device_id uuid,p_zone_key text,p_connection_type text,p_network_identifier text,
 p_ip_address inet,p_mac_address macaddr,p_vlan_reference text,p_actor_person_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device public.mme_pos_register_devices%rowtype; v_zone_id uuid; v_id uuid;
begin
 select * into v_device from public.mme_pos_register_devices where id=p_device_id for update;
 if not found then raise exception 'POS hardware device not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.network.manage',v_device.location_id) then
  raise exception 'Network administration permission denied' using errcode='42501';
 end if;
 select id into v_zone_id from public.mme_pos_network_zones where zone_key=p_zone_key and status in ('planned','active');
 if not found then raise exception 'Network zone is unavailable' using errcode='55000'; end if;
 if p_connection_type not in ('ethernet','wifi','usb_bridge','vendor_tunnel','unknown') then
  raise exception 'Unsupported connection type' using errcode='22023';
 end if;
 insert into public.mme_pos_network_devices(device_id,zone_id,connection_type,network_identifier,ip_address,mac_address,vlan_reference)
 values(p_device_id,v_zone_id,p_connection_type,p_network_identifier,p_ip_address,p_mac_address,p_vlan_reference)
 on conflict(device_id) do update set zone_id=excluded.zone_id,connection_type=excluded.connection_type,
  network_identifier=excluded.network_identifier,ip_address=excluded.ip_address,mac_address=excluded.mac_address,
  vlan_reference=excluded.vlan_reference,updated_at=now()
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_pos_record_network_connection(
 p_device_id uuid,p_connection_state text,p_authenticated boolean,p_encrypted boolean,
 p_mutual_auth boolean,p_protocol text,p_peer_identity text,p_latency_ms integer,
 p_packet_loss_percent numeric,p_observed_at timestamptz,p_source text,p_safe_detail text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_network public.mme_pos_network_devices%rowtype; v_id uuid; v_location uuid;
begin
 select n.* into v_network from public.mme_pos_network_devices n where n.device_id=p_device_id;
 select location_id into v_location from public.mme_pos_register_devices where id=p_device_id;
 if not found then raise exception 'Network device enrollment not found' using errcode='P0002'; end if;
 if p_connection_state not in ('connected','degraded','disconnected','blocked','unknown')
  or p_source not in ('trusted_agent','network_monitor','provider_webhook','manual_verification')
  or p_observed_at is null or p_observed_at<now()-interval '24 hours' or p_observed_at>now()+interval '2 minutes'
  or p_latency_ms<0 or p_latency_ms>600000 or p_packet_loss_percent<0 or p_packet_loss_percent>100 then
  raise exception 'Invalid network connection observation' using errcode='22023';
 end if;
 if p_authenticated is distinct from true or p_encrypted is distinct from true then
  insert into public.mme_pos_network_security_events(device_id,zone_id,event_type,severity,occurred_at,safe_detail)
  values(p_device_id,v_network.zone_id,case when p_authenticated is distinct from true then 'unauthenticated_peer' else 'unencrypted_session' end,
   'critical',p_observed_at,'Connection did not satisfy authentication and encryption requirements');
  insert into public.mme_pos_network_incidents(device_id,zone_id,incident_type,severity,title,safe_detail)
  values(p_device_id,v_network.zone_id,case when p_authenticated is distinct from true then 'authentication_failure' else 'encryption_missing' end,
   'critical','POS network security requirement failed','Connection quarantined pending security review');
  update public.mme_pos_network_devices set security_posture='noncompliant',updated_at=now() where device_id=p_device_id;
  raise exception 'Unauthenticated or unencrypted POS connection rejected' using errcode='42501';
 end if;
 insert into public.mme_pos_network_connections(device_id,zone_id,connection_state,authenticated,encrypted,mutual_auth,
  protocol,peer_identity,latency_ms,packet_loss_percent,observed_at,source,safe_detail)
 values(p_device_id,v_network.zone_id,p_connection_state,p_authenticated,p_encrypted,p_mutual_auth,
  p_protocol,p_peer_identity,p_latency_ms,p_packet_loss_percent,p_observed_at,p_source,left(p_safe_detail,800))
 returning id into v_id;
 update public.mme_pos_network_devices set security_posture='compliant',last_verified_at=now(),updated_at=now()
 where device_id=p_device_id;
 return v_id;
end;
$$;

create or replace function public.mme_pos_register_device_certificate(
 p_device_id uuid,p_fingerprint_sha256 text,p_issuer text,p_subject text,p_serial_reference text,
 p_secret_reference text,p_not_before timestamptz,p_expires_at timestamptz,p_actor_person_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_location uuid; v_id uuid;
begin
 select location_id into v_location from public.mme_pos_register_devices where id=p_device_id;
 if not found then raise exception 'POS device not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.network.certificates',v_location) then
  raise exception 'Certificate administration permission denied' using errcode='42501';
 end if;
 if p_fingerprint_sha256 !~ '^[a-f0-9]{64}$' or p_secret_reference is null
  or length(btrim(p_secret_reference)) not between 1 and 240
  or p_not_before is null or p_expires_at<=now() or p_expires_at<=p_not_before then
  raise exception 'Invalid certificate metadata' using errcode='22023';
 end if;
 insert into public.mme_pos_device_certificates(device_id,certificate_fingerprint_sha256,issuer,subject,
  serial_reference,secret_reference,not_before,expires_at)
 values(p_device_id,p_fingerprint_sha256,p_issuer,p_subject,p_serial_reference,p_secret_reference,p_not_before,p_expires_at)
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_pos_activate_device_certificate(
 p_certificate_id uuid,p_actor_person_id uuid,p_signature_validation_reference text
) returns text language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v public.mme_pos_device_certificates%rowtype; v_location uuid;
begin
 select * into v from public.mme_pos_device_certificates where id=p_certificate_id for update;
 if not found then raise exception 'Certificate not found' using errcode='P0002'; end if;
 select location_id into v_location from public.mme_pos_register_devices where id=v.device_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.network.certificates',v_location) then
  raise exception 'Certificate activation permission denied' using errcode='42501';
 end if;
 if v.status<>'pending' or v.not_before>now() or v.expires_at<=now()
  or p_signature_validation_reference is null or length(btrim(p_signature_validation_reference))<8 then
  raise exception 'Certificate is not eligible for activation or external validation evidence is missing' using errcode='55000';
 end if;
 update public.mme_pos_device_certificates set status='superseded'
  where device_id=v.device_id and status in ('active','expiring');
 update public.mme_pos_device_certificates set status='active',verified_by_person_id=p_actor_person_id,verified_at=now()
  where id=p_certificate_id;
 return 'active';
end;
$$;

create or replace function public.mme_pos_revoke_device_certificate(
 p_certificate_id uuid,p_actor_person_id uuid,p_reason text
) returns text language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v public.mme_pos_device_certificates%rowtype; v_location uuid;
begin
 select * into v from public.mme_pos_device_certificates where id=p_certificate_id for update;
 if not found then raise exception 'Certificate not found' using errcode='P0002'; end if;
 select location_id into v_location from public.mme_pos_register_devices where id=v.device_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.network.certificates',v_location)
  or length(btrim(coalesce(p_reason,''))) not between 8 and 800 then
  raise exception 'Certificate revocation denied or invalid reason' using errcode='42501';
 end if;
 update public.mme_pos_device_certificates set status='revoked',revoked_by_person_id=p_actor_person_id,
  revoked_at=now() where id=p_certificate_id and status not in ('revoked','superseded');
 return 'revoked';
end;
$$;

create or replace function public.mme_pos_record_network_health(
 p_device_id uuid,p_availability_percent numeric,p_latency_ms integer,p_packet_loss_percent numeric,
 p_jitter_ms integer,p_bandwidth_mbps numeric,p_certificate_days_remaining integer,
 p_health_state text,p_observed_at timestamptz,p_source text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_network public.mme_pos_network_devices%rowtype; v_id uuid;
begin
 select * into v_network from public.mme_pos_network_devices where device_id=p_device_id;
 if not found then raise exception 'Network device enrollment not found' using errcode='P0002'; end if;
 if p_health_state not in ('healthy','degraded','critical','unknown') or p_source not in ('trusted_agent','network_monitor','provider_webhook','manual_verification')
  or p_observed_at is null or p_observed_at<now()-interval '24 hours' or p_observed_at>now()+interval '2 minutes' then
  raise exception 'Invalid network health observation' using errcode='22023';
 end if;
 insert into public.mme_pos_network_health(device_id,zone_id,availability_percent,latency_ms,packet_loss_percent,
  jitter_ms,bandwidth_mbps,certificate_days_remaining,health_state,observed_at,source)
 values(p_device_id,v_network.zone_id,p_availability_percent,p_latency_ms,p_packet_loss_percent,
  p_jitter_ms,p_bandwidth_mbps,p_certificate_days_remaining,p_health_state,p_observed_at,p_source)
 returning id into v_id;
 if p_health_state in ('degraded','critical') then
  insert into public.mme_pos_network_incidents(device_id,zone_id,incident_type,severity,title,safe_detail)
  values(p_device_id,v_network.zone_id,case when p_health_state='critical' then 'connectivity_loss' else 'latency' end,
   case when p_health_state='critical' then 'high' else 'medium' end,'POS network health degraded',
   'Trusted network telemetry reports degraded connectivity; investigate before failover');
 end if;
 return v_id;
end;
$$;

revoke all on function public.mme_pos_register_network_device(uuid,text,text,text,inet,macaddr,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_record_network_connection(uuid,text,boolean,boolean,boolean,text,text,integer,numeric,timestamptz,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_register_device_certificate(uuid,text,text,text,text,text,timestamptz,timestamptz,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_activate_device_certificate(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_revoke_device_certificate(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_record_network_health(uuid,numeric,integer,numeric,integer,numeric,integer,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.mme_pos_register_network_device(uuid,text,text,text,inet,macaddr,text,uuid) to service_role;
grant execute on function public.mme_pos_record_network_connection(uuid,text,boolean,boolean,boolean,text,text,integer,numeric,timestamptz,text,text) to service_role;
grant execute on function public.mme_pos_register_device_certificate(uuid,text,text,text,text,text,timestamptz,timestamptz,uuid) to service_role;
grant execute on function public.mme_pos_activate_device_certificate(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_revoke_device_certificate(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_record_network_health(uuid,numeric,integer,numeric,integer,numeric,integer,text,timestamptz,text) to service_role;

insert into public.mme_pos_network_zones(zone_key,display_name,trust_level,description)
values
 ('pos','POS Operations','high','Register controllers and transaction operations'),
 ('payment','Payment Processing','restricted','Payment terminal and processor communication boundary'),
 ('peripherals','POS Peripherals','standard','Approved receipt printers, scanners and cash drawer peripherals'),
 ('management','Device Management','restricted','Administrative management and monitoring plane'),
 ('guest','Guest Wi-Fi','untrusted','Customer internet access; no POS trust'),
 ('infrastructure','Store Infrastructure','high','Approved store network infrastructure')
on conflict(zone_key) do nothing;

comment on table public.mme_pos_network_devices is 'Desired/observed POS network placement. Does not configure VLANs, switches, Wi-Fi or firewall rules.';
comment on table public.mme_pos_device_certificates is 'Certificate metadata and secret references only; private keys and certificate secrets remain in an external secret manager.';
comment on table public.mme_pos_network_connections is 'Trusted observations of authenticated/encrypted device connections; not proof of end-to-end network compliance.';
commit;
