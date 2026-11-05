-- Build 009.29 — POS Chargeback & Payment Dispute Intelligence Engine
-- Dispute intake, deadlines, evidence assembly and human-approved submission workflow.
-- Does not submit representments to a processor or claim a dispute win.
begin;

-- Add dispute permissions to the shared gate while retaining all inherited identity controls.
create or replace function public.mme_pos_authorize_hardware_action(
 p_actor_person_id uuid,p_permission_key text,p_location_id uuid
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $
declare v_person_status text; v_ceo_person_id uuid; v_frozen boolean; v_employment_status text;
begin
 if p_actor_person_id is null or p_location_id is null or p_permission_key not in (
  'pos.hardware.register','pos.hardware.command','pos.hardware.incident.view',
  'pos.hardware.incident.acknowledge','pos.hardware.incident.resolve','pos.hardware.admin',
  'pos.hardware.assign','pos.hardware.configure','pos.hardware.approve','pos.hardware.retire',
  'pos.network.view','pos.network.manage','pos.network.certificates','pos.network.incidents',
  'pos.security.view','pos.security.manage','pos.security.investigate','pos.security.contain','pos.security.rules.manage',
  'pos.fraud.view','pos.fraud.review','pos.fraud.rules.manage','pos.fraud.case.manage','pos.fraud.override',
  'pos.disputes.view','pos.disputes.manage','pos.disputes.evidence','pos.disputes.approve','pos.disputes.submit'
 ) then return false; end if;
 select lifecycle_status into v_person_status from public.mme_person_identities where person_id=p_actor_person_id;
 if not found or v_person_status is distinct from 'active' then return false; end if;
 select ceo_person_id,employee_access_frozen into v_ceo_person_id,v_frozen from public.employee_security_settings where singleton=true;
 if not found or v_frozen is distinct from false or v_ceo_person_id is null then return false; end if;
 select employment_status into v_employment_status from public.employee_relationships where person_id=p_actor_person_id;
 if v_employment_status is distinct from 'active' then return false; end if;
 if p_actor_person_id=v_ceo_person_id then return true; end if;
 return exists(select 1 from public.employee_permission_grants g where g.person_id=p_actor_person_id
  and g.permission_key=p_permission_key and g.revoked_at is null and (g.expires_at is null or g.expires_at>now())
  and (g.scope='{}'::jsonb or g.scope->>'location_id'=p_location_id::text));
end;
$;

create table public.mme_pos_payment_disputes (
 id uuid primary key default gen_random_uuid(),
 dispute_key text not null unique,
 provider text not null check(provider in ('stripe','verifone','other')),
 provider_dispute_reference text not null,
 provider_payment_reference text,
 provider_charge_reference text,
 location_id uuid not null,
 transaction_reference text,
 customer_reference text,
 dispute_reason_code text,
 dispute_reason text,
 currency char(3) not null check(currency ~ '^[A-Z]{3}$'),
 disputed_amount_minor bigint not null check(disputed_amount_minor>0),
 status text not null default 'received' check(status in ('received','needs_review','evidence_gathering','ready_for_approval','approved_to_submit','submitted','won','lost','withdrawn','expired','closed','error')),
 response_due_at timestamptz,
 received_at timestamptz not null,
 submitted_at timestamptz,
 provider_updated_at timestamptz,
 last_synced_at timestamptz,
 assigned_to_person_id uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(provider,provider_dispute_reference)
);
create index mme_pos_payment_disputes_deadline_idx on public.mme_pos_payment_disputes(status,response_due_at);
create index mme_pos_payment_disputes_location_idx on public.mme_pos_payment_disputes(location_id,status,received_at desc);

create table public.mme_pos_dispute_events (
 id uuid primary key default gen_random_uuid(),
 provider text not null,
 provider_event_reference text not null,
 provider_dispute_reference text,
 event_type text not null,
 payload_digest_sha256 text not null check(payload_digest_sha256 ~ '^[a-f0-9]{64}$'),
 received_at timestamptz not null default now(),
 processed_at timestamptz,
 processing_status text not null default 'received' check(processing_status in ('received','processed','ignored','failed','quarantined')),
 error_code text,
 unique(provider,provider_event_reference)
);

create table public.mme_pos_dispute_evidence (
 id uuid primary key default gen_random_uuid(),
 dispute_id uuid not null references public.mme_pos_payment_disputes(id) on delete restrict,
 evidence_type text not null check(evidence_type in ('receipt','transaction_summary','processor_authorization','processor_capture','refund_record','customer_communication','delivery_confirmation','pickup_confirmation','serial_imei_record','return_inspection','warranty_terms','refund_policy','terms_acceptance','device_register_log','other')),
 source_reference text not null check(length(btrim(source_reference)) between 3 and 500),
 storage_reference text,
 digest_sha256 text check(digest_sha256 is null or digest_sha256 ~ '^[a-f0-9]{64}$'),
 evidence_date timestamptz,
 collected_by_person_id uuid,
 collected_at timestamptz not null default now(),
 sensitivity text not null default 'confidential' check(sensitivity in ('internal','confidential','restricted')),
 admissibility_status text not null default 'unreviewed' check(admissibility_status in ('unreviewed','verified','rejected','needs_redaction')),
 reviewer_person_id uuid,
 reviewed_at timestamptz,
 review_notes text,
 created_at timestamptz not null default now()
);
create index mme_pos_dispute_evidence_case_idx on public.mme_pos_dispute_evidence(dispute_id,evidence_type);

create table public.mme_pos_dispute_packets (
 id uuid primary key default gen_random_uuid(),
 dispute_id uuid not null references public.mme_pos_payment_disputes(id) on delete restrict,
 packet_version integer not null check(packet_version>0),
 status text not null default 'draft' check(status in ('draft','validating','ready_for_approval','approved','rejected','submitted','superseded')),
 packet_manifest jsonb not null check(jsonb_typeof(packet_manifest)='object'),
 packet_digest_sha256 text check(packet_digest_sha256 is null or packet_digest_sha256 ~ '^[a-f0-9]{64}$'),
 validation_results jsonb not null default '[]'::jsonb check(jsonb_typeof(validation_results)='array'),
 generated_by_person_id uuid,
 generated_at timestamptz not null default now(),
 approved_by_person_id uuid,
 approved_at timestamptz,
 submitted_at timestamptz,
 unique(dispute_id,packet_version),
 check(approved_by_person_id is null or generated_by_person_id is null or approved_by_person_id<>generated_by_person_id)
);

create table public.mme_pos_dispute_actions (
 id uuid primary key default gen_random_uuid(),
 dispute_id uuid not null references public.mme_pos_payment_disputes(id) on delete restrict,
 packet_id uuid references public.mme_pos_dispute_packets(id) on delete restrict,
 action_type text not null check(action_type in ('request_evidence','assign_owner','approve_packet','reject_packet','submit_representment','withdraw_response','escalate_deadline','sync_provider')),
 status text not null default 'pending' check(status in ('pending','approved','rejected','executing','succeeded','failed','cancelled')),
 requested_by_person_id uuid not null,
 approved_by_person_id uuid,
 reason text not null check(length(btrim(reason)) between 8 and 1500),
 idempotency_key text not null unique,
 provider_action_reference text,
 result_summary text,
 requested_at timestamptz not null default now(),
 approved_at timestamptz,
 completed_at timestamptz,
 check(approved_by_person_id is null or approved_by_person_id<>requested_by_person_id)
);

create table public.mme_pos_dispute_audit_events (
 id uuid primary key default gen_random_uuid(),
 dispute_id uuid references public.mme_pos_payment_disputes(id) on delete restrict,
 location_id uuid not null,
 actor_person_id uuid,
 action text not null,
 reason text not null check(length(btrim(reason)) between 8 and 1500),
 object_reference text,
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
 occurred_at timestamptz not null default now()
);
create index mme_pos_dispute_audit_idx on public.mme_pos_dispute_audit_events(location_id,occurred_at desc);

alter table public.mme_pos_payment_disputes enable row level security;
alter table public.mme_pos_dispute_events enable row level security;
alter table public.mme_pos_dispute_evidence enable row level security;
alter table public.mme_pos_dispute_packets enable row level security;
alter table public.mme_pos_dispute_actions enable row level security;
alter table public.mme_pos_dispute_audit_events enable row level security;
revoke all on public.mme_pos_payment_disputes,public.mme_pos_dispute_events,public.mme_pos_dispute_evidence,
 public.mme_pos_dispute_packets,public.mme_pos_dispute_actions,public.mme_pos_dispute_audit_events from public,anon,authenticated;
grant all on public.mme_pos_payment_disputes,public.mme_pos_dispute_events,public.mme_pos_dispute_evidence,
 public.mme_pos_dispute_packets,public.mme_pos_dispute_actions,public.mme_pos_dispute_audit_events to service_role;

create or replace function public.mme_pos_authorize_dispute_action(p_actor_person_id uuid,p_location_id uuid,p_permission text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_permission not in ('pos.disputes.view','pos.disputes.manage','pos.disputes.evidence','pos.disputes.approve','pos.disputes.submit') then return false; end if;
 return public.mme_pos_authorize_hardware_action(p_actor_person_id,p_permission,p_location_id);
end;
$$;

create or replace function public.mme_pos_ingest_dispute_event(
 p_provider text,p_provider_event_reference text,p_provider_dispute_reference text,
 p_event_type text,p_payload_digest_sha256 text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
 if p_provider not in ('stripe','verifone','other') or length(btrim(coalesce(p_provider_event_reference,'')))<4
  or length(btrim(coalesce(p_event_type,'')))<3 or p_payload_digest_sha256 !~ '^[a-f0-9]{64}$' then
  raise exception 'Invalid dispute event envelope' using errcode='22023';
 end if;
 insert into public.mme_pos_dispute_events(provider,provider_event_reference,provider_dispute_reference,event_type,payload_digest_sha256)
 values(p_provider,p_provider_event_reference,p_provider_dispute_reference,p_event_type,p_payload_digest_sha256)
 on conflict(provider,provider_event_reference) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.mme_pos_dispute_events where provider=p_provider and provider_event_reference=p_provider_event_reference; end if;
 return v_id;
end;
$$;

create or replace function public.mme_pos_create_dispute_packet(
 p_dispute_id uuid,p_actor_person_id uuid,p_manifest jsonb,p_validation_results jsonb,p_digest text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_dispute public.mme_pos_payment_disputes%rowtype; v_version integer; v_id uuid;
begin
 select * into v_dispute from public.mme_pos_payment_disputes where id=p_dispute_id for update;
 if not found then raise exception 'Dispute not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_dispute_action(p_actor_person_id,v_dispute.location_id,'pos.disputes.evidence') then
  raise exception 'Dispute evidence permission denied' using errcode='42501';
 end if;
 if jsonb_typeof(p_manifest)<>'object' or jsonb_typeof(p_validation_results)<>'array'
  or p_digest is not null and p_digest !~ '^[a-f0-9]{64}$' then raise exception 'Invalid evidence packet' using errcode='22023'; end if;
 select coalesce(max(packet_version),0)+1 into v_version from public.mme_pos_dispute_packets where dispute_id=p_dispute_id;
 insert into public.mme_pos_dispute_packets(dispute_id,packet_version,packet_manifest,validation_results,packet_digest_sha256,generated_by_person_id)
 values(p_dispute_id,v_version,p_manifest,p_validation_results,p_digest,p_actor_person_id) returning id into v_id;
 update public.mme_pos_payment_disputes set status='evidence_gathering',updated_at=now() where id=p_dispute_id;
 insert into public.mme_pos_dispute_audit_events(dispute_id,location_id,actor_person_id,action,reason,object_reference)
 values(p_dispute_id,v_dispute.location_id,p_actor_person_id,'packet_generated','Evidence packet generated and awaits validation.',v_id::text);
 return v_id;
end;
$$;

create or replace function public.mme_pos_approve_dispute_packet(
 p_packet_id uuid,p_approver_person_id uuid,p_reason text
) returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_packet public.mme_pos_dispute_packets%rowtype; v_dispute public.mme_pos_payment_disputes%rowtype;
begin
 select * into v_packet from public.mme_pos_dispute_packets where id=p_packet_id for update;
 if not found then raise exception 'Dispute packet not found' using errcode='P0002'; end if;
 select * into v_dispute from public.mme_pos_payment_disputes where id=v_packet.dispute_id for update;
 if not public.mme_pos_authorize_dispute_action(p_approver_person_id,v_dispute.location_id,'pos.disputes.approve') then
  raise exception 'Dispute approval permission denied' using errcode='42501';
 end if;
 if p_approver_person_id=v_packet.generated_by_person_id or length(btrim(coalesce(p_reason,'')))<8 then
  raise exception 'Independent approval and reason required' using errcode='42501';
 end if;
 if v_packet.status not in ('ready_for_approval','validating') or jsonb_array_length(v_packet.validation_results)>0 then
  raise exception 'Packet validation is not clear for approval' using errcode='55000';
 end if;
 update public.mme_pos_dispute_packets set status='approved',approved_by_person_id=p_approver_person_id,approved_at=now() where id=p_packet_id;
 update public.mme_pos_payment_disputes set status='approved_to_submit',updated_at=now() where id=v_dispute.id;
 insert into public.mme_pos_dispute_audit_events(dispute_id,location_id,actor_person_id,action,reason,object_reference)
 values(v_dispute.id,v_dispute.location_id,p_approver_person_id,'packet_approved',p_reason,p_packet_id::text);
 return true;
end;
$$;

revoke all on function public.mme_pos_authorize_dispute_action(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_ingest_dispute_event(text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_create_dispute_packet(uuid,uuid,jsonb,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_approve_dispute_packet(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_pos_authorize_dispute_action(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_ingest_dispute_event(text,text,text,text,text) to service_role;
grant execute on function public.mme_pos_create_dispute_packet(uuid,uuid,jsonb,jsonb,text) to service_role;
grant execute on function public.mme_pos_approve_dispute_packet(uuid,uuid,text) to service_role;

comment on table public.mme_pos_payment_disputes is 'Processor dispute lifecycle and response deadlines; provider sync is performed only by separately configured trusted connectors.';
comment on table public.mme_pos_dispute_packets is 'Versioned evidence manifest; source artifacts must remain in approved encrypted storage.';
comment on table public.mme_pos_dispute_actions is 'Audited, idempotent dispute actions; submission requires independent approval and a trusted provider adapter.';
commit;
