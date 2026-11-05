-- Build 009.23: hardware fleet inventory, assignment, lifecycle, configuration and governed administration.
begin;

alter table public.mme_pos_register_devices
 add column manufacturer text check(manufacturer is null or length(manufacturer)<=100),
 add column model text check(model is null or length(model)<=120),
 add column serial_number text check(serial_number is null or length(serial_number)<=160),
 add column firmware_version text check(firmware_version is null or length(firmware_version)<=80),
 add column adapter_version text check(adapter_version is null or length(adapter_version)<=80),
 add column warranty_expires_at date,
 add column installed_at timestamptz,
 add column retired_at timestamptz,
 add column hardware_notes text check(hardware_notes is null or length(hardware_notes)<=1000);
create unique index mme_pos_hardware_serial_unique
 on public.mme_pos_register_devices(serial_number) where serial_number is not null;
create index mme_pos_hardware_fleet_location_type_idx
 on public.mme_pos_register_devices(location_id,device_type,status);

create table public.mme_pos_device_assignments (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 location_id uuid not null,
 register_reference text not null check(length(btrim(register_reference)) between 1 and 80),
 assigned_by_person_id uuid not null,
 assigned_at timestamptz not null default now(),
 unassigned_at timestamptz,
 reason text check(reason is null or length(reason)<=500),
 check(unassigned_at is null or unassigned_at>=assigned_at)
);
create unique index mme_pos_device_one_active_assignment
 on public.mme_pos_device_assignments(device_id) where unassigned_at is null;
create index mme_pos_device_assignments_location_idx
 on public.mme_pos_device_assignments(location_id,register_reference,assigned_at desc);

create table public.mme_pos_device_lifecycle_events (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 from_status text,
 to_status text not null check(to_status in ('pending','online','offline','maintenance','retired')),
 event_type text not null check(event_type in ('registered','verified','activated','maintenance_started','maintenance_completed','suspended','reassigned','retired','reactivated')),
 actor_person_id uuid not null,
 reason text not null check(length(btrim(reason)) between 8 and 800),
 approval_id uuid,
 created_at timestamptz not null default now()
);
create index mme_pos_device_lifecycle_events_device_idx
 on public.mme_pos_device_lifecycle_events(device_id,created_at desc);

create table public.mme_pos_device_configuration_versions (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 version_number integer not null check(version_number>0),
 configuration jsonb not null check(jsonb_typeof(configuration)='object' and octet_length(configuration::text)<=12000),
 configuration_digest text not null check(configuration_digest ~ '^[a-f0-9]{64}$'),
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','rejected','applied','rolled_back','cancelled')),
 created_by_person_id uuid not null,
 approved_by_person_id uuid,
 created_at timestamptz not null default now(),
 approved_at timestamptz,
 applied_at timestamptz,
 unique(device_id,version_number),
 check(approved_by_person_id is null or approved_by_person_id<>created_by_person_id)
);
create index mme_pos_device_config_queue_idx
 on public.mme_pos_device_configuration_versions(status,created_at);

create table public.mme_pos_device_admin_approvals (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 action_type text not null check(action_type in ('activate','reassign','configuration','maintenance','retire','reactivate')),
 requested_by_person_id uuid not null,
 approved_by_person_id uuid,
 status text not null default 'pending' check(status in ('pending','approved','rejected','expired','cancelled')),
 reason text not null check(length(btrim(reason)) between 8 and 800),
 payload jsonb not null default '{}'::jsonb check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=12000),
 expires_at timestamptz not null default now()+interval '24 hours',
 created_at timestamptz not null default now(),
 decided_at timestamptz,
 check(approved_by_person_id is null or approved_by_person_id<>requested_by_person_id)
);
create index mme_pos_device_admin_approval_queue_idx
 on public.mme_pos_device_admin_approvals(status,created_at);

create table public.mme_pos_device_admin_actions (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 actor_person_id uuid not null,
 approval_id uuid references public.mme_pos_device_admin_approvals(id) on delete restrict,
 action_type text not null check(action_type in ('view_diagnostics','run_diagnostic','update_metadata','assign','unassign','maintenance','activate','retire','propose_configuration','apply_configuration')),
 outcome text not null check(outcome in ('accepted','rejected','completed','failed')),
 safe_detail text check(safe_detail is null or length(safe_detail)<=1000),
 created_at timestamptz not null default now()
);
create index mme_pos_device_admin_actions_device_idx
 on public.mme_pos_device_admin_actions(device_id,created_at desc);

alter table public.mme_pos_device_assignments enable row level security;
alter table public.mme_pos_device_lifecycle_events enable row level security;
alter table public.mme_pos_device_configuration_versions enable row level security;
alter table public.mme_pos_device_admin_approvals enable row level security;
alter table public.mme_pos_device_admin_actions enable row level security;
revoke all on public.mme_pos_device_assignments,public.mme_pos_device_lifecycle_events,
 public.mme_pos_device_configuration_versions,public.mme_pos_device_admin_approvals,
 public.mme_pos_device_admin_actions from public,anon,authenticated;
grant all on public.mme_pos_device_assignments,public.mme_pos_device_lifecycle_events,
 public.mme_pos_device_configuration_versions,public.mme_pos_device_admin_approvals,
 public.mme_pos_device_admin_actions to service_role;

-- Extend the existing permission gate while preserving active identity, employment and CEO freeze checks.
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
  'pos.hardware.approve','pos.hardware.retire'
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

create or replace function public.mme_pos_request_device_admin_approval(
 p_device_id uuid,p_actor_person_id uuid,p_action_type text,p_reason text,p_payload jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device public.mme_pos_register_devices%rowtype; v_permission text; v_id uuid;
begin
 if p_device_id is null or p_actor_person_id is null
  or p_action_type not in ('activate','reassign','configuration','maintenance','retire','reactivate')
  or length(btrim(coalesce(p_reason,''))) not between 8 and 800
  or p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>12000 then
  raise exception 'Invalid hardware administration approval request' using errcode='22023';
 end if;
 select * into v_device from public.mme_pos_register_devices where id=p_device_id for update;
 if not found then raise exception 'Hardware device not found' using errcode='P0002'; end if;
 v_permission:=case when p_action_type='retire' then 'pos.hardware.retire'
  when p_action_type='reassign' then 'pos.hardware.assign'
  when p_action_type='configuration' then 'pos.hardware.configure'
  else 'pos.hardware.admin' end;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,v_permission,v_device.location_id) then
  raise exception 'Hardware administration permission denied' using errcode='42501';
 end if;
 insert into public.mme_pos_device_admin_approvals(device_id,action_type,requested_by_person_id,reason,payload)
 values(p_device_id,p_action_type,p_actor_person_id,btrim(p_reason),p_payload) returning id into v_id;
 insert into public.mme_pos_device_admin_actions(device_id,actor_person_id,action_type,outcome,safe_detail)
 values(p_device_id,p_actor_person_id,'update_metadata','accepted','Approval request created: '||p_action_type);
 return v_id;
end;
$$;

create or replace function public.mme_pos_decide_device_admin_approval(
 p_approval_id uuid,p_actor_person_id uuid,p_decision text,p_note text default null
) returns text
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v public.mme_pos_device_admin_approvals%rowtype; v_location uuid;
begin
 if p_approval_id is null or p_actor_person_id is null or p_decision not in ('approve','reject') then
  raise exception 'Invalid approval decision' using errcode='22023';
 end if;
 select * into v from public.mme_pos_device_admin_approvals where id=p_approval_id for update;
 if not found then raise exception 'Approval request not found' using errcode='P0002'; end if;
 select location_id into v_location from public.mme_pos_register_devices where id=v.device_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.approve',v_location) then
  raise exception 'Hardware approval permission denied' using errcode='42501';
 end if;
 if v.status<>'pending' or v.expires_at<=now() then
  if v.status='pending' then update public.mme_pos_device_admin_approvals set status='expired' where id=v.id; end if;
  raise exception 'Approval is no longer pending or has expired' using errcode='55000';
 end if;
 if v.requested_by_person_id=p_actor_person_id then
  raise exception 'Requester cannot approve their own hardware administration request' using errcode='42501';
 end if;
 update public.mme_pos_device_admin_approvals set status=case when p_decision='approve' then 'approved' else 'rejected' end,
  approved_by_person_id=p_actor_person_id,decided_at=now() where id=v.id;
 insert into public.mme_pos_device_admin_actions(device_id,actor_person_id,approval_id,action_type,outcome,safe_detail)
 values(v.device_id,p_actor_person_id,v.id,'update_metadata',case when p_decision='approve' then 'completed' else 'rejected' end,left(p_note,1000));
 return case when p_decision='approve' then 'approved' else 'rejected' end;
end;
$$;

create or replace function public.mme_pos_assign_hardware_device(
 p_device_id uuid,p_actor_person_id uuid,p_location_id uuid,p_register_reference text,p_reason text,p_approval_id uuid
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device public.mme_pos_register_devices%rowtype; v_approval public.mme_pos_device_admin_approvals%rowtype; v_id uuid;
begin
 if p_device_id is null or p_actor_person_id is null or p_location_id is null
  or length(btrim(coalesce(p_register_reference,''))) not between 1 and 80
  or length(btrim(coalesce(p_reason,''))) not between 8 and 500 then
  raise exception 'Invalid hardware assignment' using errcode='22023';
 end if;
 select * into v_device from public.mme_pos_register_devices where id=p_device_id for update;
 if not found or v_device.status='retired' then raise exception 'Device is unavailable for assignment' using errcode='55000'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.assign',v_device.location_id)
  or not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.assign',p_location_id) then
  raise exception 'Hardware assignment permission denied for source or destination location' using errcode='42501';
 end if;
 if p_approval_id is not null then
  select * into v_approval from public.mme_pos_device_admin_approvals where id=p_approval_id for update;
  if not found or v_approval.device_id<>p_device_id or v_approval.action_type<>'reassign'
   or v_approval.status<>'approved' then raise exception 'Approved reassignment request is required' using errcode='42501'; end if;
 else
  raise exception 'Approved reassignment request is required' using errcode='42501';
 end if;
 update public.mme_pos_device_assignments set unassigned_at=now(),reason=left(p_reason,500)
  where device_id=p_device_id and unassigned_at is null;
 insert into public.mme_pos_device_assignments(device_id,location_id,register_reference,assigned_by_person_id,reason)
 values(p_device_id,p_location_id,btrim(p_register_reference),p_actor_person_id,left(p_reason,500)) returning id into v_id;
 update public.mme_pos_register_devices set location_id=p_location_id,register_reference=btrim(p_register_reference),updated_at=now()
  where id=p_device_id;
 insert into public.mme_pos_device_lifecycle_events(device_id,from_status,to_status,event_type,actor_person_id,reason,approval_id)
 values(p_device_id,v_device.status,v_device.status,'reassigned',p_actor_person_id,left(p_reason,800),p_approval_id);
 insert into public.mme_pos_device_admin_actions(device_id,actor_person_id,approval_id,action_type,outcome,safe_detail)
 values(p_device_id,p_actor_person_id,p_approval_id,'assign','completed',left(p_reason,1000));
 return v_id;
end;
$$;

create or replace function public.mme_pos_set_hardware_device_lifecycle(
 p_device_id uuid,p_actor_person_id uuid,p_new_status text,p_reason text,p_approval_id uuid default null
) returns text
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device public.mme_pos_register_devices%rowtype; v_approval public.mme_pos_device_admin_approvals%rowtype;
 v_permission text; v_event text;
begin
 if p_device_id is null or p_actor_person_id is null
  or p_new_status not in ('online','maintenance','retired','pending')
  or length(btrim(coalesce(p_reason,''))) not between 8 and 800 then
  raise exception 'Invalid hardware lifecycle transition' using errcode='22023';
 end if;
 select * into v_device from public.mme_pos_register_devices where id=p_device_id for update;
 if not found then raise exception 'Hardware device not found' using errcode='P0002'; end if;
 v_permission:=case when p_new_status='retired' then 'pos.hardware.retire' else 'pos.hardware.admin' end;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,v_permission,v_device.location_id) then
  raise exception 'Hardware lifecycle permission denied' using errcode='42501';
 end if;
 if p_approval_id is null then raise exception 'Approved lifecycle request is required' using errcode='42501'; end if;
 select * into v_approval from public.mme_pos_device_admin_approvals where id=p_approval_id for update;
 if not found or v_approval.device_id<>p_device_id or v_approval.status<>'approved'
  or v_approval.action_type not in ('activate','maintenance','retire','reactivate') then
  raise exception 'Approved lifecycle request does not match this device' using errcode='42501';
 end if;
 if v_device.status='retired' and p_new_status<>'pending' then raise exception 'Retired device must be reactivated through pending enrollment' using errcode='55000'; end if;
 if v_device.status=p_new_status then raise exception 'Device already has requested lifecycle state' using errcode='23514'; end if;
 v_event:=case when p_new_status='retired' then 'retired' when p_new_status='maintenance' then 'maintenance_started'
  when p_new_status='online' then 'activated' else 'suspended' end;
 update public.mme_pos_register_devices set status=p_new_status,
  retired_at=case when p_new_status='retired' then now() when p_new_status='pending' then null else retired_at end,
  updated_at=now() where id=p_device_id;
 insert into public.mme_pos_device_lifecycle_events(device_id,from_status,to_status,event_type,actor_person_id,reason,approval_id)
 values(p_device_id,v_device.status,p_new_status,v_event,p_actor_person_id,left(p_reason,800),p_approval_id);
 insert into public.mme_pos_device_admin_actions(device_id,actor_person_id,approval_id,action_type,outcome,safe_detail)
 values(p_device_id,p_actor_person_id,p_approval_id,case when p_new_status='retired' then 'retire' else 'maintenance' end,'completed',left(p_reason,1000));
 return p_new_status;
end;
$$;

create or replace function public.mme_pos_propose_hardware_configuration(
 p_device_id uuid,p_actor_person_id uuid,p_configuration jsonb,p_digest text
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_device public.mme_pos_register_devices%rowtype; v_version integer; v_id uuid;
begin
 if p_device_id is null or p_actor_person_id is null or p_configuration is null
  or jsonb_typeof(p_configuration)<>'object' or octet_length(p_configuration::text)>12000
  or p_digest !~ '^[a-f0-9]{64}$' then raise exception 'Invalid device configuration proposal' using errcode='22023'; end if;
 select * into v_device from public.mme_pos_register_devices where id=p_device_id for update;
 if not found or v_device.status='retired' then raise exception 'Device is unavailable' using errcode='55000'; end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.configure',v_device.location_id) then
  raise exception 'Device configuration permission denied' using errcode='42501';
 end if;
 select coalesce(max(version_number),0)+1 into v_version from public.mme_pos_device_configuration_versions where device_id=p_device_id;
 insert into public.mme_pos_device_configuration_versions(device_id,version_number,configuration,configuration_digest,status,created_by_person_id)
 values(p_device_id,v_version,p_configuration,p_digest,'pending_approval',p_actor_person_id) returning id into v_id;
 insert into public.mme_pos_device_admin_actions(device_id,actor_person_id,action_type,outcome,safe_detail)
 values(p_device_id,p_actor_person_id,'propose_configuration','accepted','Configuration proposal version '||v_version||' awaiting approval');
 return v_id;
end;
$$;

create or replace function public.mme_pos_approve_hardware_configuration(
 p_configuration_id uuid,p_actor_person_id uuid
) returns text
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v public.mme_pos_device_configuration_versions%rowtype; v_location uuid;
begin
 select * into v from public.mme_pos_device_configuration_versions where id=p_configuration_id for update;
 if not found then raise exception 'Configuration proposal not found' using errcode='P0002'; end if;
 select location_id into v_location from public.mme_pos_register_devices where id=v.device_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.approve',v_location) then
  raise exception 'Configuration approval permission denied' using errcode='42501';
 end if;
 if v.status<>'pending_approval' or v.created_by_person_id=p_actor_person_id then
  raise exception 'Configuration must be approved by a different authorized person' using errcode='42501';
 end if;
 update public.mme_pos_device_configuration_versions set status='approved',approved_by_person_id=p_actor_person_id,approved_at=now()
  where id=p_configuration_id;
 insert into public.mme_pos_device_admin_actions(device_id,actor_person_id,action_type,outcome,safe_detail)
 values(v.device_id,p_actor_person_id,'propose_configuration','completed','Approved configuration version '||v.version_number||'; application remains a separate verified deployment operation');
 return 'approved_pending_deployment';
end;
$$;

revoke all on function public.mme_pos_authorize_hardware_action(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_request_device_admin_approval(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.mme_pos_decide_device_admin_approval(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_assign_hardware_device(uuid,uuid,uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_set_hardware_device_lifecycle(uuid,uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_propose_hardware_configuration(uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_approve_hardware_configuration(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_pos_authorize_hardware_action(uuid,text,uuid) to service_role;
grant execute on function public.mme_pos_request_device_admin_approval(uuid,uuid,text,text,jsonb) to service_role;
grant execute on function public.mme_pos_decide_device_admin_approval(uuid,uuid,text,text) to service_role;
grant execute on function public.mme_pos_assign_hardware_device(uuid,uuid,uuid,text,text,uuid) to service_role;
grant execute on function public.mme_pos_set_hardware_device_lifecycle(uuid,uuid,text,text,uuid) to service_role;
grant execute on function public.mme_pos_propose_hardware_configuration(uuid,uuid,jsonb,text) to service_role;
grant execute on function public.mme_pos_approve_hardware_configuration(uuid,uuid) to service_role;

comment on table public.mme_pos_device_admin_approvals is 'Two-person approvals for sensitive hardware fleet operations; requesters cannot approve their own requests.';
comment on table public.mme_pos_device_configuration_versions is 'Versioned configuration proposals; approval does not itself apply configuration to hardware.';
comment on table public.mme_pos_device_admin_actions is 'Append-only operational record of authorized hardware administration actions.';
commit;
