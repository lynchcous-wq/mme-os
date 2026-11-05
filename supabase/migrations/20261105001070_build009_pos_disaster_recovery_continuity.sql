-- Build 009.26: POS network disaster recovery, transaction continuity journal and recovery verification.
-- Records recovery intent and reconciliation evidence; does not perform payment failover or restore production systems.
begin;

create table public.mme_pos_disaster_incidents (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 incident_key text not null unique check(length(btrim(incident_key)) between 8 and 160),
 incident_type text not null check(incident_type in ('network_outage','payment_connectivity','database_unavailable','store_power_loss','device_fleet_outage','data_integrity','regional_provider_outage','other')),
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'detected' check(status in ('detected','assessed','declared','recovering','monitoring','resolved','closed')),
 detected_at timestamptz not null,
 declared_at timestamptz,
 resolved_at timestamptz,
 affected_services text[] not null default '{}',
 impact_summary text not null check(length(btrim(impact_summary)) between 8 and 2000),
 incident_commander_person_id uuid,
 created_by_person_id uuid,
 resolution_summary text check(resolution_summary is null or length(resolution_summary)<=2000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(resolved_at is null or resolved_at>=detected_at)
);
create index mme_pos_disaster_incidents_queue_idx on public.mme_pos_disaster_incidents(location_id,status,severity,detected_at desc);

create table public.mme_pos_recovery_plans (
 id uuid primary key default gen_random_uuid(),
 plan_key text not null unique check(length(btrim(plan_key)) between 3 and 120),
 service_key text not null check(length(btrim(service_key)) between 2 and 100),
 location_id uuid,
 recovery_priority integer not null check(recovery_priority between 1 and 10),
 target_rto_minutes integer not null check(target_rto_minutes between 1 and 10080),
 target_rpo_minutes integer not null check(target_rpo_minutes between 0 and 10080),
 approved_runbook_reference text not null check(length(btrim(approved_runbook_reference)) between 3 and 240),
 dependencies text[] not null default '{}',
 status text not null default 'draft' check(status in ('draft','approved','suspended','retired')),
 approved_by_person_id uuid,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((status='approved' and approved_by_person_id is not null and approved_at is not null) or status<>'approved')
);
create index mme_pos_recovery_plans_service_idx on public.mme_pos_recovery_plans(service_key,status);

create table public.mme_pos_recovery_executions (
 id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_pos_disaster_incidents(id) on delete restrict,
 plan_id uuid not null references public.mme_pos_recovery_plans(id) on delete restrict,
 location_id uuid not null,
 status text not null default 'pending_approval' check(status in ('pending_approval','approved','in_progress','blocked','verification_pending','succeeded','failed','cancelled')),
 requested_by_person_id uuid not null,
 approved_by_person_id uuid,
 started_at timestamptz,
 completed_at timestamptz,
 actual_rto_minutes integer,
 actual_rpo_minutes integer,
 recovery_point_reference text,
 execution_reference text,
 outcome_summary text check(outcome_summary is null or length(outcome_summary)<=2000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(approved_by_person_id is null or approved_by_person_id<>requested_by_person_id),
 check(completed_at is null or (started_at is not null and completed_at>=started_at))
);
create index mme_pos_recovery_execution_queue_idx on public.mme_pos_recovery_executions(location_id,status,created_at desc);

create table public.mme_pos_recovery_approvals (
 id uuid primary key default gen_random_uuid(),
 execution_id uuid not null references public.mme_pos_recovery_executions(id) on delete restrict,
 requested_by_person_id uuid not null,
 decided_by_person_id uuid,
 decision text not null default 'pending' check(decision in ('pending','approved','rejected','expired')),
 reason text not null check(length(btrim(reason)) between 8 and 1000),
 expires_at timestamptz not null,
 decided_at timestamptz,
 created_at timestamptz not null default now(),
 check(decided_by_person_id is null or decided_by_person_id<>requested_by_person_id),
 check((decision='pending' and decided_at is null and decided_by_person_id is null) or (decision<>'pending' and decided_at is not null))
);
create index mme_pos_recovery_approval_queue_idx on public.mme_pos_recovery_approvals(decision,expires_at);

create table public.mme_pos_transaction_journal (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 register_reference text not null check(length(btrim(register_reference)) between 1 and 120),
 transaction_reference text not null check(length(btrim(transaction_reference)) between 1 and 160),
 employee_person_id uuid,
 occurred_at timestamptz not null,
 journaled_at timestamptz not null default now(),
 transaction_type text not null check(transaction_type in ('sale','refund','void','exchange','payment_adjustment')),
 currency_code char(3) not null,
 gross_amount numeric(14,2) not null check(gross_amount>=0),
 tax_amount numeric(14,2) not null check(tax_amount>=0),
 transaction_status text not null check(transaction_status in ('initiated','pending_payment','authorized','captured','declined','voided','refunded','cancelled','unknown')),
 payment_status text not null check(payment_status in ('not_required','pending','authorized','captured','declined','voided','refunded','uncertain','reconciliation_required')),
 processor_reference text check(processor_reference is null or length(processor_reference)<=200),
 processor_token_reference text check(processor_token_reference is null or length(processor_token_reference)<=200),
 item_summary jsonb not null default '[]'::jsonb check(jsonb_typeof(item_summary)='array'),
 inventory_sync_status text not null default 'pending' check(inventory_sync_status in ('pending','synced','conflict','not_applicable')),
 reconciliation_status text not null default 'pending' check(reconciliation_status in ('pending','matched','mismatch','duplicate_suspected','manual_review')),
 source_system text not null check(source_system in ('pos','offline_queue','processor_webhook','reconciliation_worker','manual_recovery')),
 idempotency_key text not null check(length(btrim(idempotency_key)) between 8 and 200),
 payload_digest_sha256 text check(payload_digest_sha256 is null or payload_digest_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default now(),
 unique(location_id,register_reference,transaction_reference),
 unique(idempotency_key)
);
create index mme_pos_transaction_journal_recovery_idx on public.mme_pos_transaction_journal(location_id,reconciliation_status,payment_status,occurred_at desc);

create table public.mme_pos_continuity_events (
 id uuid primary key default gen_random_uuid(),
 incident_id uuid references public.mme_pos_disaster_incidents(id) on delete restrict,
 location_id uuid not null,
 event_type text not null check(event_type in ('offline_mode_started','offline_mode_ended','transaction_queued','transaction_replayed','payment_reconciled','inventory_reconciled','duplicate_detected','conflict_detected','service_restored','manual_override')),
 severity text not null check(severity in ('info','warning','high','critical')),
 transaction_journal_id uuid references public.mme_pos_transaction_journal(id) on delete restrict,
 event_reference text,
 details text not null check(length(btrim(details)) between 3 and 1200),
 occurred_at timestamptz not null,
 recorded_at timestamptz not null default now(),
 actor_person_id uuid
);
create index mme_pos_continuity_events_location_time_idx on public.mme_pos_continuity_events(location_id,occurred_at desc);

create table public.mme_pos_backup_registry (
 id uuid primary key default gen_random_uuid(),
 backup_reference text not null unique check(length(btrim(backup_reference)) between 8 and 240),
 service_key text not null check(length(btrim(service_key)) between 2 and 100),
 location_id uuid,
 storage_provider text not null check(length(btrim(storage_provider)) between 2 and 120),
 storage_object_reference text not null check(length(btrim(storage_object_reference)) between 3 and 500),
 encryption_key_reference text not null check(length(btrim(encryption_key_reference)) between 3 and 240),
 checksum_sha256 text not null check(checksum_sha256 ~ '^[a-f0-9]{64}$'),
 backup_size_bytes bigint check(backup_size_bytes is null or backup_size_bytes>=0),
 backup_started_at timestamptz not null,
 backup_completed_at timestamptz,
 backup_state text not null check(backup_state in ('created','completed','failed','expired','quarantined')),
 immutable_retention_until timestamptz,
 created_at timestamptz not null default now(),
 check(backup_completed_at is null or backup_completed_at>=backup_started_at)
);
create index mme_pos_backup_registry_service_idx on public.mme_pos_backup_registry(service_key,backup_completed_at desc);

create table public.mme_pos_backup_verifications (
 id uuid primary key default gen_random_uuid(),
 backup_id uuid not null references public.mme_pos_backup_registry(id) on delete restrict,
 verification_type text not null check(verification_type in ('checksum','decryptability','restore_test','integrity','retention')),
 verification_status text not null check(verification_status in ('pending','passed','failed','inconclusive')),
 verified_by_reference text not null check(length(btrim(verified_by_reference)) between 3 and 240),
 verified_at timestamptz not null,
 duration_seconds integer check(duration_seconds is null or duration_seconds>=0),
 safe_result text check(safe_result is null or length(safe_result)<=1200),
 created_at timestamptz not null default now()
);
create index mme_pos_backup_verification_time_idx on public.mme_pos_backup_verifications(backup_id,verified_at desc);

create table public.mme_pos_recovery_verification (
 id uuid primary key default gen_random_uuid(),
 execution_id uuid not null references public.mme_pos_recovery_executions(id) on delete restrict,
 verification_key text not null check(length(btrim(verification_key)) between 3 and 120),
 verification_status text not null check(verification_status in ('pending','passed','failed','waived')),
 evidence_reference text not null check(length(btrim(evidence_reference)) between 3 and 240),
 verified_by_person_id uuid,
 verified_at timestamptz,
 notes text check(notes is null or length(notes)<=1200),
 created_at timestamptz not null default now(),
 unique(execution_id,verification_key),
 check((verification_status='pending' and verified_at is null) or (verification_status<>'pending' and verified_at is not null))
);
create index mme_pos_recovery_verification_execution_idx on public.mme_pos_recovery_verification(execution_id,verification_status);

alter table public.mme_pos_disaster_incidents enable row level security;
alter table public.mme_pos_recovery_plans enable row level security;
alter table public.mme_pos_recovery_executions enable row level security;
alter table public.mme_pos_recovery_approvals enable row level security;
alter table public.mme_pos_transaction_journal enable row level security;
alter table public.mme_pos_continuity_events enable row level security;
alter table public.mme_pos_backup_registry enable row level security;
alter table public.mme_pos_backup_verifications enable row level security;
alter table public.mme_pos_recovery_verification enable row level security;
revoke all on public.mme_pos_disaster_incidents,public.mme_pos_recovery_plans,public.mme_pos_recovery_executions,
 public.mme_pos_recovery_approvals,public.mme_pos_transaction_journal,public.mme_pos_continuity_events,
 public.mme_pos_backup_registry,public.mme_pos_backup_verifications,public.mme_pos_recovery_verification
 from public,anon,authenticated;
grant all on public.mme_pos_disaster_incidents,public.mme_pos_recovery_plans,public.mme_pos_recovery_executions,
 public.mme_pos_recovery_approvals,public.mme_pos_transaction_journal,public.mme_pos_continuity_events,
 public.mme_pos_backup_registry,public.mme_pos_backup_verifications,public.mme_pos_recovery_verification to service_role;

create or replace function public.mme_pos_authorize_recovery_action(p_actor_person_id uuid,p_location_id uuid,p_permission text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_permission not in ('pos.network.view','pos.network.manage','pos.network.incidents','pos.hardware.incident.resolve') then return false; end if;
 return public.mme_pos_authorize_hardware_action(p_actor_person_id,p_permission,p_location_id);
end;
$$;

create or replace function public.mme_pos_record_transaction_journal(
 p_location_id uuid,p_register_reference text,p_transaction_reference text,p_employee_person_id uuid,
 p_occurred_at timestamptz,p_transaction_type text,p_currency_code text,p_gross_amount numeric,p_tax_amount numeric,
 p_transaction_status text,p_payment_status text,p_processor_reference text,p_processor_token_reference text,
 p_item_summary jsonb,p_inventory_sync_status text,p_source_system text,p_idempotency_key text,p_payload_digest_sha256 text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
 if p_location_id is null or p_register_reference is null or p_transaction_reference is null or p_occurred_at is null
  or p_gross_amount<0 or p_tax_amount<0 or p_currency_code !~ '^[A-Z]{3}$'
  or p_item_summary is null or jsonb_typeof(p_item_summary)<>'array'
  or p_idempotency_key is null or length(btrim(p_idempotency_key))<8
  or p_payload_digest_sha256 is not null and p_payload_digest_sha256 !~ '^[a-f0-9]{64}$' then
  raise exception 'Invalid transaction journal payload' using errcode='22023';
 end if;
 if p_transaction_status='captured' and p_payment_status<>'captured' then
  raise exception 'Captured sale requires confirmed captured payment state' using errcode='23514';
 end if;
 if p_payment_status in ('pending','authorized','uncertain','reconciliation_required') and p_transaction_status='captured' then
  raise exception 'Unconfirmed payment cannot complete a sale' using errcode='23514';
 end if;
 insert into public.mme_pos_transaction_journal(location_id,register_reference,transaction_reference,employee_person_id,
  occurred_at,transaction_type,currency_code,gross_amount,tax_amount,transaction_status,payment_status,
  processor_reference,processor_token_reference,item_summary,inventory_sync_status,source_system,idempotency_key,payload_digest_sha256)
 values(p_location_id,p_register_reference,p_transaction_reference,p_employee_person_id,p_occurred_at,p_transaction_type,
  p_currency_code,p_gross_amount,p_tax_amount,p_transaction_status,p_payment_status,p_processor_reference,
  p_processor_token_reference,coalesce(p_item_summary,'[]'::jsonb),p_inventory_sync_status,p_source_system,p_idempotency_key,p_payload_digest_sha256)
 on conflict(idempotency_key) do nothing returning id into v_id;
 if v_id is null then
  select id into v_id from public.mme_pos_transaction_journal where idempotency_key=p_idempotency_key;
  if not exists(select 1 from public.mme_pos_transaction_journal where id=v_id and location_id=p_location_id
   and register_reference=p_register_reference and transaction_reference=p_transaction_reference) then
   raise exception 'Idempotency key reused for a different transaction' using errcode='23505';
  end if;
 end if;
 return v_id;
end;
$$;

create or replace function public.mme_pos_request_recovery_execution(
 p_incident_id uuid,p_plan_id uuid,p_actor_person_id uuid,p_reason text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_incident public.mme_pos_disaster_incidents%rowtype; v_plan public.mme_pos_recovery_plans%rowtype; v_id uuid; v_approval uuid;
begin
 select * into v_incident from public.mme_pos_disaster_incidents where id=p_incident_id for update;
 if not found then raise exception 'Disaster incident not found' using errcode='P0002'; end if;
 select * into v_plan from public.mme_pos_recovery_plans where id=p_plan_id and status='approved';
 if not found then raise exception 'Approved recovery plan not found' using errcode='P0002'; end if;
 if v_plan.location_id is not null and v_plan.location_id<>v_incident.location_id then
  raise exception 'Recovery plan location does not match incident' using errcode='42501';
 end if;
 if not public.mme_pos_authorize_recovery_action(p_actor_person_id,v_incident.location_id,'pos.network.manage')
  or length(btrim(coalesce(p_reason,''))) not between 8 and 1000 then
  raise exception 'Recovery request permission denied or reason missing' using errcode='42501';
 end if;
 insert into public.mme_pos_recovery_executions(incident_id,plan_id,location_id,requested_by_person_id)
 values(p_incident_id,p_plan_id,v_incident.location_id,p_actor_person_id) returning id into v_id;
 insert into public.mme_pos_recovery_approvals(execution_id,requested_by_person_id,reason,expires_at)
 values(v_id,p_actor_person_id,p_reason,now()+interval '24 hours') returning id into v_approval;
 return v_id;
end;
$$;

create or replace function public.mme_pos_decide_recovery_approval(
 p_approval_id uuid,p_actor_person_id uuid,p_decision text
) returns text language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v public.mme_pos_recovery_approvals%rowtype; v_execution public.mme_pos_recovery_executions%rowtype;
begin
 select * into v from public.mme_pos_recovery_approvals where id=p_approval_id for update;
 if not found then raise exception 'Recovery approval not found' using errcode='P0002'; end if;
 select * into v_execution from public.mme_pos_recovery_executions where id=v.execution_id for update;
 if not public.mme_pos_authorize_recovery_action(p_actor_person_id,v_execution.location_id,'pos.network.manage')
  or p_decision not in ('approve','reject') then
  raise exception 'Recovery approval permission denied' using errcode='42501';
 end if;
 if v.decision<>'pending' or v.expires_at<=now() or v.requested_by_person_id=p_actor_person_id then
  raise exception 'Approval is expired, already decided, or self-approval was attempted' using errcode='42501';
 end if;
 update public.mme_pos_recovery_approvals set decision=case when p_decision='approve' then 'approved' else 'rejected' end,
  decided_by_person_id=p_actor_person_id,decided_at=now() where id=p_approval_id;
 update public.mme_pos_recovery_executions set status=case when p_decision='approve' then 'approved' else 'cancelled' end,
  approved_by_person_id=case when p_decision='approve' then p_actor_person_id else null end,updated_at=now()
  where id=v.execution_id;
 return case when p_decision='approve' then 'approved_pending_execution' else 'rejected' end;
end;
$$;

create or replace function public.mme_pos_finalize_recovery_execution(p_execution_id uuid,p_actor_person_id uuid,p_outcome_summary text)
returns text language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v public.mme_pos_recovery_executions%rowtype; v_pending integer;
begin
 select * into v from public.mme_pos_recovery_executions where id=p_execution_id for update;
 if not found then raise exception 'Recovery execution not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_recovery_action(p_actor_person_id,v.location_id,'pos.network.manage') then
  raise exception 'Recovery finalization permission denied' using errcode='42501';
 end if;
 if v.status not in ('verification_pending','in_progress') then raise exception 'Recovery is not ready for verification' using errcode='55000'; end if;
 select count(*) into v_pending from public.mme_pos_recovery_verification where execution_id=p_execution_id
  and verification_status not in ('passed');
 if v_pending>0 or not exists(select 1 from public.mme_pos_recovery_verification where execution_id=p_execution_id) then
  update public.mme_pos_recovery_executions set status='blocked',outcome_summary='Required recovery verification incomplete',updated_at=now()
   where id=p_execution_id;
  return 'blocked_verification_incomplete';
 end if;
 update public.mme_pos_recovery_executions set status='succeeded',completed_at=now(),outcome_summary=left(p_outcome_summary,2000),updated_at=now()
  where id=p_execution_id;
 update public.mme_pos_disaster_incidents set status='monitoring',updated_at=now() where id=v.incident_id;
 return 'succeeded_monitoring';
end;
$$;

revoke all on function public.mme_pos_authorize_recovery_action(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_record_transaction_journal(uuid,text,text,uuid,timestamptz,text,text,numeric,numeric,text,text,text,text,jsonb,text,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_request_recovery_execution(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_decide_recovery_approval(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_finalize_recovery_execution(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mme_pos_authorize_recovery_action(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_record_transaction_journal(uuid,text,text,uuid,timestamptz,text,text,numeric,numeric,text,text,text,text,jsonb,text,text,text,text) to service_role;
grant execute on function public.mme_pos_request_recovery_execution(uuid,uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_decide_recovery_approval(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_finalize_recovery_execution(uuid,uuid,text) to service_role;

comment on table public.mme_pos_transaction_journal is 'Idempotent transaction continuity journal. Never store PAN, CVV, PIN, magnetic-stripe data or raw cardholder data.';
comment on table public.mme_pos_backup_registry is 'Backup inventory metadata and external object/key references; backup bytes and keys remain outside this database.';
comment on table public.mme_pos_recovery_executions is 'Approved recovery intent and evidence; a trusted worker must execute the external runbook.';
commit;
