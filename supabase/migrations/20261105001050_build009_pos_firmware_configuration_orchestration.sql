-- Build 009.24: signed firmware/configuration catalog, staged rollout and recovery orchestration.
-- This creates governed rollout records. It does not itself upload firmware or contact physical devices.
begin;

create table public.mme_pos_firmware_packages (
 id uuid primary key default gen_random_uuid(),
 package_key text not null,
 version text not null check(length(btrim(version)) between 1 and 80),
 manufacturer text not null check(length(btrim(manufacturer)) between 1 and 100),
 model text not null check(length(btrim(model)) between 1 and 120),
 device_type text not null check(device_type in ('cash_drawer','receipt_printer','payment_terminal','register_controller')),
 hardware_revision text,
 minimum_current_version text,
 maximum_current_version text,
 target_firmware_version text not null check(length(btrim(target_firmware_version)) between 1 and 80),
 artifact_storage_key text not null check(length(btrim(artifact_storage_key)) between 1 and 500),
 artifact_sha256 text not null check(artifact_sha256 ~ '^[a-f0-9]{64}$'),
 signature_storage_key text not null check(length(btrim(signature_storage_key)) between 1 and 500),
 signature_verified boolean not null default false,
 signature_verified_by_person_id uuid,
 signature_verified_at timestamptz,
 publisher text not null check(length(btrim(publisher)) between 1 and 160),
 release_notes text check(release_notes is null or length(release_notes)<=4000),
 requires_reboot boolean not null default false,
 supports_rollback boolean not null default false,
 rollback_package_id uuid references public.mme_pos_firmware_packages(id) on delete restrict,
 status text not null default 'draft' check(status in ('draft','quarantined','verified','revoked','retired')),
 created_by_person_id uuid not null,
 created_at timestamptz not null default now(),
 unique(package_key,version,manufacturer,model),
 check((signature_verified=false and signature_verified_at is null and signature_verified_by_person_id is null)
    or (signature_verified=true and signature_verified_at is not null and signature_verified_by_person_id is not null)),
 check(rollback_package_id is null or rollback_package_id<>id)
);
create index mme_pos_firmware_package_compatibility_idx
 on public.mme_pos_firmware_packages(manufacturer,model,device_type,status);

create table public.mme_pos_configuration_templates (
 id uuid primary key default gen_random_uuid(),
 template_key text not null,
 version_number integer not null check(version_number>0),
 manufacturer text,
 model text,
 device_type text not null check(device_type in ('cash_drawer','receipt_printer','payment_terminal','register_controller')),
 configuration jsonb not null check(jsonb_typeof(configuration)='object' and octet_length(configuration::text)<=12000),
 configuration_digest text not null check(configuration_digest ~ '^[a-f0-9]{64}$'),
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','revoked')),
 created_by_person_id uuid not null,
 approved_by_person_id uuid,
 created_at timestamptz not null default now(),
 approved_at timestamptz,
 unique(template_key,version_number),
 check(approved_by_person_id is null or approved_by_person_id<>created_by_person_id)
);

create table public.mme_pos_deployment_campaigns (
 id uuid primary key default gen_random_uuid(),
 campaign_name text not null check(length(btrim(campaign_name)) between 3 and 160),
 deployment_type text not null check(deployment_type in ('firmware','configuration')),
 firmware_package_id uuid references public.mme_pos_firmware_packages(id) on delete restrict,
 configuration_template_id uuid references public.mme_pos_configuration_templates(id) on delete restrict,
 rollout_stage text not null default 'lab' check(rollout_stage in ('lab','canary','pilot','regional','enterprise')),
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','scheduled','running','paused','completed','failed','cancelled','rolled_back')),
 requested_by_person_id uuid not null,
 approved_by_person_id uuid,
 approval_expires_at timestamptz,
 scheduled_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 failure_reason text check(failure_reason is null or length(failure_reason)<=1200),
 max_failure_rate numeric(5,2) not null default 5 check(max_failure_rate between 0 and 100),
 minimum_success_count integer not null default 1 check(minimum_success_count between 1 and 10000),
 created_at timestamptz not null default now(),
 check((deployment_type='firmware' and firmware_package_id is not null and configuration_template_id is null)
    or (deployment_type='configuration' and configuration_template_id is not null and firmware_package_id is null)),
 check(approved_by_person_id is null or approved_by_person_id<>requested_by_person_id)
);
create index mme_pos_deployment_campaign_queue_idx
 on public.mme_pos_deployment_campaigns(status,rollout_stage,scheduled_at);

create table public.mme_pos_deployment_targets (
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.mme_pos_deployment_campaigns(id) on delete restrict,
 device_id uuid not null references public.mme_pos_register_devices(id) on delete restrict,
 stage_order integer not null check(stage_order>=0),
 status text not null default 'pending' check(status in ('pending','preflight','blocked','ready','dispatched','acknowledged','succeeded','failed','uncertain','skipped','recovery_pending','recovered')),
 current_version text,
 target_version text not null,
 idle_verified_at timestamptz,
 compatibility_verified_at timestamptz,
 dispatched_at timestamptz,
 completed_at timestamptz,
 failure_code text,
 safe_result text check(safe_result is null or length(safe_result)<=1000),
 unique(campaign_id,device_id)
);
create index mme_pos_deployment_targets_queue_idx
 on public.mme_pos_deployment_targets(campaign_id,status,stage_order);

create table public.mme_pos_deployment_events (
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.mme_pos_deployment_campaigns(id) on delete restrict,
 target_id uuid references public.mme_pos_deployment_targets(id) on delete restrict,
 device_id uuid references public.mme_pos_register_devices(id) on delete restrict,
 event_type text not null check(event_type in ('campaign_created','approval_requested','approved','rejected','stage_started','preflight_passed','preflight_blocked','dispatched','acknowledged','succeeded','failed','paused','resumed','cancelled','recovery_requested','recovered','recovery_failed','integrity_check_failed')),
 event_detail text check(event_detail is null or length(event_detail)<=1200),
 actor_person_id uuid,
 created_at timestamptz not null default now()
);
create index mme_pos_deployment_events_campaign_idx on public.mme_pos_deployment_events(campaign_id,created_at desc);

create table public.mme_pos_deployment_approvals (
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.mme_pos_deployment_campaigns(id) on delete restrict,
 requested_by_person_id uuid not null,
 decided_by_person_id uuid,
 decision text not null default 'pending' check(decision in ('pending','approved','rejected','expired')),
 reason text not null check(length(btrim(reason)) between 8 and 800),
 expires_at timestamptz not null default now()+interval '24 hours',
 created_at timestamptz not null default now(),
 decided_at timestamptz,
 check(decided_by_person_id is null or decided_by_person_id<>requested_by_person_id)
);
create unique index mme_pos_deployment_one_pending_approval
 on public.mme_pos_deployment_approvals(campaign_id) where decision='pending';

create table public.mme_pos_deployment_recovery (
 id uuid primary key default gen_random_uuid(),
 target_id uuid not null references public.mme_pos_deployment_targets(id) on delete restrict,
 recovery_type text not null check(recovery_type in ('vendor_rollback','reinstall_previous_version','manual_vendor_recovery')),
 status text not null default 'pending_approval' check(status in ('pending_approval','approved','dispatched','succeeded','failed','unsupported','cancelled')),
 previous_version text,
 recovery_package_id uuid references public.mme_pos_firmware_packages(id) on delete restrict,
 vendor_support_verified boolean not null default false,
 requested_by_person_id uuid not null,
 approved_by_person_id uuid,
 reason text not null check(length(btrim(reason)) between 8 and 800),
 created_at timestamptz not null default now(),
 completed_at timestamptz,
 check(approved_by_person_id is null or approved_by_person_id<>requested_by_person_id)
);

alter table public.mme_pos_firmware_packages enable row level security;
alter table public.mme_pos_configuration_templates enable row level security;
alter table public.mme_pos_deployment_campaigns enable row level security;
alter table public.mme_pos_deployment_targets enable row level security;
alter table public.mme_pos_deployment_events enable row level security;
alter table public.mme_pos_deployment_approvals enable row level security;
alter table public.mme_pos_deployment_recovery enable row level security;
revoke all on public.mme_pos_firmware_packages,public.mme_pos_configuration_templates,
 public.mme_pos_deployment_campaigns,public.mme_pos_deployment_targets,
 public.mme_pos_deployment_events,public.mme_pos_deployment_approvals,
 public.mme_pos_deployment_recovery from public,anon,authenticated;
grant all on public.mme_pos_firmware_packages,public.mme_pos_configuration_templates,
 public.mme_pos_deployment_campaigns,public.mme_pos_deployment_targets,
 public.mme_pos_deployment_events,public.mme_pos_deployment_approvals,
 public.mme_pos_deployment_recovery to service_role;

create or replace function public.mme_pos_create_deployment_campaign(
 p_actor_person_id uuid,p_campaign_name text,p_deployment_type text,p_stage text,
 p_firmware_package_id uuid,p_configuration_template_id uuid,p_device_ids uuid[],
 p_max_failure_rate numeric default 5
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid; v_device record; v_target_version text; v_location uuid; v_permission text;
begin
 if p_actor_person_id is null or length(btrim(coalesce(p_campaign_name,''))) not between 3 and 160
  or p_deployment_type not in ('firmware','configuration')
  or p_stage not in ('lab','canary','pilot','regional','enterprise')
  or coalesce(array_length(p_device_ids,1),0) not between 1 and 500
  or p_max_failure_rate not between 0 and 100 then
  raise exception 'Invalid deployment campaign' using errcode='22023';
 end if;
 if cardinality(p_device_ids)<>(select count(distinct x) from unnest(p_device_ids) x) then
  raise exception 'Duplicate devices in deployment campaign' using errcode='22023';
 end if;
 if p_deployment_type='firmware' then
  select target_firmware_version into v_target_version from public.mme_pos_firmware_packages
   where id=p_firmware_package_id and status='verified' and signature_verified=true;
  if not found then raise exception 'Verified signed firmware package is required' using errcode='55000'; end if;
 elsif p_deployment_type='configuration' then
  select version_number::text into v_target_version from public.mme_pos_configuration_templates
   where id=p_configuration_template_id and status='approved';
  if not found then raise exception 'Approved configuration template is required' using errcode='55000'; end if;
 else raise exception 'Unsupported deployment type' using errcode='22023'; end if;
 insert into public.mme_pos_deployment_campaigns(campaign_name,deployment_type,firmware_package_id,
  configuration_template_id,rollout_stage,requested_by_person_id,max_failure_rate)
 values(btrim(p_campaign_name),p_deployment_type,p_firmware_package_id,p_configuration_template_id,
  p_stage,p_actor_person_id,p_max_failure_rate) returning id into v_id;
 for v_device in select d.* from public.mme_pos_register_devices d where d.id=any(p_device_ids) order by d.id
 loop
  if v_device.status<>'online' or v_device.status='retired' then
   raise exception 'Every campaign device must be online and non-retired' using errcode='55000';
  end if;
  if p_deployment_type='firmware' and not exists(select 1 from public.mme_pos_firmware_packages f
    where f.id=p_firmware_package_id and f.manufacturer=v_device.manufacturer and f.model=v_device.model
     and f.device_type=v_device.device_type) then
   raise exception 'Firmware package is incompatible with a selected device' using errcode='23514';
  end if;
  if p_deployment_type='configuration' and not exists(select 1 from public.mme_pos_configuration_templates t
    where t.id=p_configuration_template_id and t.device_type=v_device.device_type
     and (t.manufacturer is null or t.manufacturer=v_device.manufacturer)
     and (t.model is null or t.model=v_device.model)) then
   raise exception 'Configuration template is incompatible with a selected device' using errcode='23514';
  end if;
  v_permission:='pos.hardware.configure';
  if not public.mme_pos_authorize_hardware_action(p_actor_person_id,v_permission,v_device.location_id) then
   raise exception 'Deployment permission denied for one or more device locations' using errcode='42501';
  end if;
  insert into public.mme_pos_deployment_targets(campaign_id,device_id,stage_order,current_version,target_version)
  values(v_id,v_device.id,0,v_device.firmware_version,v_target_version);
 end loop;
 update public.mme_pos_deployment_campaigns set status='pending_approval' where id=v_id;
 insert into public.mme_pos_deployment_approvals(campaign_id,requested_by_person_id,reason)
 values(v_id,p_actor_person_id,'Approval requested for staged hardware deployment');
 insert into public.mme_pos_deployment_events(campaign_id,event_type,actor_person_id,event_detail)
 values(v_id,'campaign_created',p_actor_person_id,'Targets registered; physical deployment has not started');
 return v_id;
end;
$$;

create or replace function public.mme_pos_decide_deployment_approval(
 p_approval_id uuid,p_actor_person_id uuid,p_decision text
) returns text
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v public.mme_pos_deployment_approvals%rowtype; v_campaign public.mme_pos_deployment_campaigns%rowtype;
declare v_location uuid;
begin
 if p_approval_id is null or p_actor_person_id is null or p_decision not in ('approve','reject') then
  raise exception 'Invalid deployment approval decision' using errcode='22023';
 end if;
 select * into v from public.mme_pos_deployment_approvals where id=p_approval_id for update;
 if not found then raise exception 'Deployment approval not found' using errcode='P0002'; end if;
 select * into v_campaign from public.mme_pos_deployment_campaigns where id=v.campaign_id for update;
 if v.decision<>'pending' or v.expires_at<=now() then
  if v.decision='pending' then update public.mme_pos_deployment_approvals set decision='expired' where id=v.id; end if;
  raise exception 'Deployment approval expired or already decided' using errcode='55000';
 end if;
 if v.requested_by_person_id=p_actor_person_id then raise exception 'Requester cannot approve own deployment' using errcode='42501'; end if;
 if not exists(select 1 from public.mme_pos_deployment_targets t join public.mme_pos_register_devices d on d.id=t.device_id
  where t.campaign_id=v.campaign_id and public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.approve',d.location_id)) then
  raise exception 'Deployment approval permission denied' using errcode='42501';
 end if;
 update public.mme_pos_deployment_approvals set decision=case when p_decision='approve' then 'approved' else 'rejected' end,
  decided_by_person_id=p_actor_person_id,decided_at=now() where id=v.id;
 update public.mme_pos_deployment_campaigns set status=case when p_decision='approve' then 'approved' else 'cancelled' end,
  approved_by_person_id=case when p_decision='approve' then p_actor_person_id else null end,
  approval_expires_at=v.expires_at where id=v.campaign_id;
 insert into public.mme_pos_deployment_events(campaign_id,event_type,actor_person_id,event_detail)
 values(v.campaign_id,case when p_decision='approve' then 'approved' else 'rejected' end,p_actor_person_id,'Separate approver decision recorded');
 return case when p_decision='approve' then 'approved' else 'rejected' end;
end;
$$;

create or replace function public.mme_pos_record_deployment_preflight(
 p_target_id uuid,p_actor_person_id uuid,p_idle_verified boolean,p_compatibility_verified boolean,
 p_verification_at timestamptz
) returns text
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_target public.mme_pos_deployment_targets%rowtype; v_campaign public.mme_pos_deployment_campaigns%rowtype;
declare v_location uuid;
begin
 if p_target_id is null or p_actor_person_id is null or p_idle_verified is distinct from true
  or p_compatibility_verified is distinct from true or p_verification_at is null
  or p_verification_at<now()-interval '2 minutes' or p_verification_at>now()+interval '30 seconds' then
  raise exception 'Fresh idle and compatibility verification required' using errcode='22023';
 end if;
 select * into v_target from public.mme_pos_deployment_targets where id=p_target_id for update;
 if not found then raise exception 'Deployment target not found' using errcode='P0002'; end if;
 select * into v_campaign from public.mme_pos_deployment_campaigns where id=v_target.campaign_id for update;
 select location_id into v_location from public.mme_pos_register_devices where id=v_target.device_id;
 if v_campaign.status not in ('approved','running') or v_campaign.approval_expires_at<=now() then
  raise exception 'Campaign is not approved or approval has expired' using errcode='55000';
 end if;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.configure',v_location) then
  raise exception 'Preflight permission denied' using errcode='42501';
 end if;
 update public.mme_pos_deployment_targets set status='ready',idle_verified_at=p_verification_at,
  compatibility_verified_at=p_verification_at where id=p_target_id;
 insert into public.mme_pos_deployment_events(campaign_id,target_id,device_id,event_type,actor_person_id,event_detail)
 values(v_target.campaign_id,p_target_id,v_target.device_id,'preflight_passed',p_actor_person_id,
  'Idle state and model compatibility verified by trusted deployment adapter');
 return 'ready';
end;
$$;

create or replace function public.mme_pos_authorize_deployment_dispatch(p_target_id uuid)
returns boolean
language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_target public.mme_pos_deployment_targets%rowtype; v_campaign public.mme_pos_deployment_campaigns%rowtype;
begin
 select * into v_target from public.mme_pos_deployment_targets where id=p_target_id;
 if not found or v_target.status<>'ready' or v_target.idle_verified_at<now()-interval '2 minutes'
  or v_target.compatibility_verified_at<now()-interval '2 minutes' then return false; end if;
 select * into v_campaign from public.mme_pos_deployment_campaigns where id=v_target.campaign_id;
 if v_campaign.status not in ('approved','running') or v_campaign.approval_expires_at<=now() then return false; end if;
 if v_campaign.deployment_type='firmware' then
  return exists(select 1 from public.mme_pos_firmware_packages f where f.id=v_campaign.firmware_package_id
   and f.status='verified' and f.signature_verified=true);
 end if;
 return exists(select 1 from public.mme_pos_configuration_templates t where t.id=v_campaign.configuration_template_id and t.status='approved');
end;
$$;

create or replace function public.mme_pos_pause_deployment_on_failure(p_campaign_id uuid)
returns text language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_campaign public.mme_pos_deployment_campaigns%rowtype; v_total integer; v_failed integer; v_rate numeric;
begin
 select * into v_campaign from public.mme_pos_deployment_campaigns where id=p_campaign_id for update;
 if not found then raise exception 'Deployment campaign not found' using errcode='P0002'; end if;
 select count(*),count(*) filter(where status in ('failed','uncertain')) into v_total,v_failed
  from public.mme_pos_deployment_targets where campaign_id=p_campaign_id and status not in ('pending','skipped');
 v_rate:=case when v_total=0 then 0 else v_failed::numeric*100/v_total end;
 if v_rate>v_campaign.max_failure_rate then
  update public.mme_pos_deployment_campaigns set status='paused',failure_reason='Configured failure-rate threshold exceeded' where id=p_campaign_id;
  update public.mme_pos_deployment_targets set status='blocked'
   where campaign_id=p_campaign_id and status in ('pending','ready');
  insert into public.mme_pos_deployment_events(campaign_id,event_type,event_detail)
  values(p_campaign_id,'paused','Automatic pause: configured failure-rate threshold exceeded');
  return 'paused';
 end if;
 return 'within_threshold';
end;
$$;

create or replace function public.mme_pos_request_deployment_recovery(
 p_target_id uuid,p_actor_person_id uuid,p_recovery_type text,p_reason text,
 p_recovery_package_id uuid default null,p_vendor_support_verified boolean default false
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_target public.mme_pos_deployment_targets%rowtype; v_campaign public.mme_pos_deployment_campaigns%rowtype;
declare v_id uuid; v_location uuid;
begin
 if p_target_id is null or p_actor_person_id is null
  or p_recovery_type not in ('vendor_rollback','reinstall_previous_version','manual_vendor_recovery')
  or length(btrim(coalesce(p_reason,''))) not between 8 and 800 then
  raise exception 'Invalid recovery request' using errcode='22023';
 end if;
 select * into v_target from public.mme_pos_deployment_targets where id=p_target_id for update;
 if not found then raise exception 'Deployment target not found' using errcode='P0002'; end if;
 select * into v_campaign from public.mme_pos_deployment_campaigns where id=v_target.campaign_id;
 select location_id into v_location from public.mme_pos_register_devices where id=v_target.device_id;
 if not public.mme_pos_authorize_hardware_action(p_actor_person_id,'pos.hardware.configure',v_location) then
  raise exception 'Recovery permission denied' using errcode='42501';
 end if;
 if p_recovery_type='vendor_rollback' and p_vendor_support_verified is distinct from true then
  raise exception 'Vendor-supported rollback must be verified before request' using errcode='55000';
 end if;
 if p_recovery_type='reinstall_previous_version' and p_recovery_package_id is null then
  raise exception 'Verified previous firmware package is required' using errcode='22023';
 end if;
 if p_recovery_package_id is not null and not exists(select 1 from public.mme_pos_firmware_packages
   where id=p_recovery_package_id and status='verified' and signature_verified=true) then
  raise exception 'Recovery firmware package is not verified' using errcode='55000';
 end if;
 insert into public.mme_pos_deployment_recovery(target_id,recovery_type,previous_version,recovery_package_id,
  vendor_support_verified,requested_by_person_id,reason)
 values(p_target_id,p_recovery_type,v_target.current_version,p_recovery_package_id,p_vendor_support_verified,
  p_actor_person_id,btrim(p_reason)) returning id into v_id;
 update public.mme_pos_deployment_targets set status='recovery_pending' where id=p_target_id;
 insert into public.mme_pos_deployment_events(campaign_id,target_id,device_id,event_type,actor_person_id,event_detail)
 values(v_campaign.id,p_target_id,v_target.device_id,'recovery_requested',p_actor_person_id,
  'Recovery requires separate approval and verified vendor support');
 return v_id;
end;
$$;

revoke all on function public.mme_pos_create_deployment_campaign(uuid,text,text,text,uuid,uuid,uuid[],numeric) from public,anon,authenticated;
revoke all on function public.mme_pos_decide_deployment_approval(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_record_deployment_preflight(uuid,uuid,boolean,boolean,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_pos_authorize_deployment_dispatch(uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_pause_deployment_on_failure(uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_request_deployment_recovery(uuid,uuid,text,text,uuid,boolean) from public,anon,authenticated;
grant execute on function public.mme_pos_create_deployment_campaign(uuid,text,text,text,uuid,uuid,uuid[],numeric) to service_role;
grant execute on function public.mme_pos_decide_deployment_approval(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_record_deployment_preflight(uuid,uuid,boolean,boolean,timestamptz) to service_role;
grant execute on function public.mme_pos_authorize_deployment_dispatch(uuid) to service_role;
grant execute on function public.mme_pos_pause_deployment_on_failure(uuid) to service_role;
grant execute on function public.mme_pos_request_deployment_recovery(uuid,uuid,text,text,uuid,boolean) to service_role;

comment on table public.mme_pos_firmware_packages is 'Firmware artifact metadata and integrity evidence; artifact bytes remain in controlled object storage.';
comment on table public.mme_pos_deployment_campaigns is 'Approved staged rollout plans; campaign records alone do not contact hardware.';
comment on table public.mme_pos_deployment_recovery is 'Recovery requests require separate approval and verified vendor support; rollback is never assumed.';
commit;
