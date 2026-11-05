-- Build 009.28 — POS Fraud Detection & Transaction Anomaly Intelligence Engine
-- Detection and case workflow only: no autonomous accusation, disciplinary action or customer lockout.
begin;

create table public.mme_pos_fraud_rules (
 id uuid primary key default gen_random_uuid(),
 rule_key text not null,
 rule_version integer not null default 1 check(rule_version>0),
 rule_name text not null check(length(btrim(rule_name)) between 3 and 180),
 category text not null check(category in ('refund_pattern','void_pattern','discount_override','drawer_activity','payment_velocity','duplicate_payment','split_tender','serial_imei_mismatch','return_condition','cash_variance','employee_register_pattern','other')),
 description text not null check(length(btrim(description)) between 8 and 2000),
 rule_definition jsonb not null check(jsonb_typeof(rule_definition)='object'),
 severity text not null check(severity in ('low','medium','high','critical')),
 enabled boolean not null default false,
 requires_human_review boolean not null default true,
 created_by_person_id uuid,
 approved_by_person_id uuid,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(rule_key,rule_version),
 check(enabled=false or (approved_by_person_id is not null and approved_at is not null))
);

create table public.mme_pos_fraud_events (
 id uuid primary key default gen_random_uuid(),
 event_key text not null unique,
 location_id uuid not null,
 register_reference text,
 transaction_reference text,
 related_transaction_reference text,
 employee_person_id uuid,
 customer_reference text,
 device_reference text,
 event_type text not null check(event_type in ('sale','refund','return','void','discount_override','price_override','drawer_open','no_sale_drawer_open','payment_decline','payment_authorization','payment_capture','payment_reversal','split_tender','chargeback_notice','serial_mismatch','imei_mismatch','condition_mismatch','other')),
 tender_type text,
 amount_minor bigint check(amount_minor is null or amount_minor>=0),
 currency char(3),
 processor_reference_token text,
 item_reference text,
 item_serial_masked text,
 item_imei_masked text,
 observed_at timestamptz not null,
 received_at timestamptz not null default now(),
 source_system text not null,
 details jsonb not null default '{}'::jsonb check(jsonb_typeof(details)='object'),
 payload_digest_sha256 text check(payload_digest_sha256 is null or payload_digest_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default now(),
 check(amount_minor is null or currency ~ '^[A-Z]{3}$'),
 check(item_serial_masked is null or length(item_serial_masked)<=80),
 check(item_imei_masked is null or length(item_imei_masked)<=32)
);
create index mme_pos_fraud_events_store_time_idx on public.mme_pos_fraud_events(location_id,observed_at desc);
create index mme_pos_fraud_events_employee_time_idx on public.mme_pos_fraud_events(location_id,employee_person_id,observed_at desc);
create index mme_pos_fraud_events_transaction_idx on public.mme_pos_fraud_events(location_id,transaction_reference,event_type);

create table public.mme_pos_fraud_assessments (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.mme_pos_fraud_events(id) on delete restrict,
 location_id uuid not null,
 rule_id uuid references public.mme_pos_fraud_rules(id) on delete restrict,
 rule_version integer,
 risk_score integer not null check(risk_score between 0 and 100),
 risk_band text not null check(risk_band in ('informational','low','moderate','high','critical')),
 explanation text not null check(length(btrim(explanation)) between 8 and 2000),
 contributing_factors jsonb not null check(jsonb_typeof(contributing_factors)='array'),
 model_or_ruleset_version text not null,
 assessed_at timestamptz not null default now(),
 expires_at timestamptz,
 human_review_required boolean not null default true,
 check(expires_at is null or expires_at>assessed_at)
);
create index mme_pos_fraud_assessments_location_idx on public.mme_pos_fraud_assessments(location_id,risk_band,assessed_at desc);

create table public.mme_pos_fraud_cases (
 id uuid primary key default gen_random_uuid(),
 case_key text not null unique,
 location_id uuid not null,
 title text not null check(length(btrim(title)) between 3 and 180),
 case_category text not null,
 status text not null default 'new' check(status in ('new','triage','investigating','awaiting_evidence','review','resolved','closed','false_positive','inconclusive')),
 priority text not null check(priority in ('low','normal','high','urgent')),
 summary text not null check(length(btrim(summary)) between 8 and 3000),
 assigned_to_person_id uuid,
 opened_by_person_id uuid,
 linked_transaction_reference text,
 subject_employee_person_id uuid,
 subject_customer_reference text,
 opened_at timestamptz not null default now(),
 resolved_at timestamptz,
 closed_at timestamptz,
 resolution_code text check(resolution_code is null or resolution_code in ('confirmed_loss','no_loss','policy_gap','training_gap','false_positive','unsubstantiated','inconclusive','referred_to_processor')),
 resolution_summary text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_pos_fraud_cases_queue_idx on public.mme_pos_fraud_cases(location_id,status,priority,opened_at desc);

create table public.mme_pos_fraud_case_events (
 case_id uuid not null references public.mme_pos_fraud_cases(id) on delete restrict,
 event_id uuid not null references public.mme_pos_fraud_events(id) on delete restrict,
 linked_at timestamptz not null default now(),
 linked_by_person_id uuid,
 primary key(case_id,event_id)
);

create table public.mme_pos_fraud_evidence (
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.mme_pos_fraud_cases(id) on delete restrict,
 event_id uuid references public.mme_pos_fraud_events(id) on delete restrict,
 evidence_type text not null check(evidence_type in ('receipt_reference','processor_reference','inventory_record','serial_test_result','return_condition_record','camera_reference','cash_drawer_log','register_audit','other')),
 evidence_reference text not null check(length(btrim(evidence_reference)) between 3 and 500),
 digest_sha256 text check(digest_sha256 is null or digest_sha256 ~ '^[a-f0-9]{64}$'),
 collected_by_person_id uuid,
 collected_at timestamptz not null,
 sensitivity text not null default 'internal' check(sensitivity in ('internal','confidential','restricted')),
 custody_log jsonb not null default '[]'::jsonb check(jsonb_typeof(custody_log)='array'),
 retention_until timestamptz,
 created_at timestamptz not null default now()
);
create index mme_pos_fraud_evidence_case_idx on public.mme_pos_fraud_evidence(case_id,collected_at);

create table public.mme_pos_fraud_reviews (
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.mme_pos_fraud_cases(id) on delete restrict,
 reviewer_person_id uuid not null,
 decision text not null check(decision in ('continue_review','confirmed_policy_violation','confirmed_loss','no_loss','false_positive','unsubstantiated','inconclusive','refer_to_processor')),
 rationale text not null check(length(btrim(rationale)) between 8 and 3000),
 evidence_reviewed jsonb not null default '[]'::jsonb check(jsonb_typeof(evidence_reviewed)='array'),
 reviewed_at timestamptz not null default now()
);
create index mme_pos_fraud_reviews_case_idx on public.mme_pos_fraud_reviews(case_id,reviewed_at desc);

create table public.mme_pos_fraud_outcomes (
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null unique references public.mme_pos_fraud_cases(id) on delete restrict,
 outcome text not null check(outcome in ('confirmed_loss','no_loss','policy_gap','training_gap','false_positive','unsubstantiated','inconclusive','referred_to_processor')),
 loss_amount_minor bigint check(loss_amount_minor is null or loss_amount_minor>=0),
 currency char(3),
 recovery_amount_minor bigint check(recovery_amount_minor is null or recovery_amount_minor>=0),
 corrective_action_reference text,
 approved_by_person_id uuid not null,
 approved_at timestamptz not null,
 notes text check(notes is null or length(notes)<=3000),
 created_at timestamptz not null default now(),
 check((loss_amount_minor is null and currency is null) or (loss_amount_minor is not null and currency ~ '^[A-Z]{3}$'))
);

create table public.mme_pos_fraud_audit_events (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 actor_person_id uuid,
 action text not null,
 object_type text not null,
 object_reference text not null,
 reason text not null check(length(btrim(reason)) between 8 and 1200),
 occurred_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object')
);
create index mme_pos_fraud_audit_location_idx on public.mme_pos_fraud_audit_events(location_id,occurred_at desc);

alter table public.mme_pos_fraud_rules enable row level security;
alter table public.mme_pos_fraud_events enable row level security;
alter table public.mme_pos_fraud_assessments enable row level security;
alter table public.mme_pos_fraud_cases enable row level security;
alter table public.mme_pos_fraud_case_events enable row level security;
alter table public.mme_pos_fraud_evidence enable row level security;
alter table public.mme_pos_fraud_reviews enable row level security;
alter table public.mme_pos_fraud_outcomes enable row level security;
alter table public.mme_pos_fraud_audit_events enable row level security;

revoke all on public.mme_pos_fraud_rules,public.mme_pos_fraud_events,public.mme_pos_fraud_assessments,
 public.mme_pos_fraud_cases,public.mme_pos_fraud_case_events,public.mme_pos_fraud_evidence,
 public.mme_pos_fraud_reviews,public.mme_pos_fraud_outcomes,public.mme_pos_fraud_audit_events from public,anon,authenticated;
grant all on public.mme_pos_fraud_rules,public.mme_pos_fraud_events,public.mme_pos_fraud_assessments,
 public.mme_pos_fraud_cases,public.mme_pos_fraud_case_events,public.mme_pos_fraud_evidence,
 public.mme_pos_fraud_reviews,public.mme_pos_fraud_outcomes,public.mme_pos_fraud_audit_events to service_role;

create or replace function public.mme_pos_authorize_fraud_action(p_actor_person_id uuid,p_location_id uuid,p_permission text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_permission not in ('pos.fraud.view','pos.fraud.review','pos.fraud.rules.manage','pos.fraud.case.manage','pos.fraud.override') then return false; end if;
 return public.mme_pos_authorize_hardware_action(p_actor_person_id,p_permission,p_location_id);
end;
$$;

create or replace function public.mme_pos_ingest_fraud_event(
 p_event_key text,p_location_id uuid,p_register_reference text,p_transaction_reference text,
 p_related_transaction_reference text,p_employee_person_id uuid,p_customer_reference text,p_device_reference text,
 p_event_type text,p_tender_type text,p_amount_minor bigint,p_currency text,p_processor_reference_token text,
 p_item_reference text,p_item_serial_masked text,p_item_imei_masked text,p_observed_at timestamptz,
 p_source_system text,p_details jsonb,p_payload_digest_sha256 text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
 if length(btrim(coalesce(p_event_key,'')))<8 or p_location_id is null or p_observed_at is null
  or p_observed_at>now()+interval '5 minutes' or p_amount_minor<0
  or p_details is null or jsonb_typeof(p_details)<>'object'
  or p_details::text ~* '"(pan|card_number|full_card_number|cvv|cvc|pin|track_data|magstripe)"'
  or p_payload_digest_sha256 is not null and p_payload_digest_sha256 !~ '^[a-f0-9]{64}$' then
  raise exception 'Invalid or sensitive fraud event payload' using errcode='22023';
 end if;
 insert into public.mme_pos_fraud_events(event_key,location_id,register_reference,transaction_reference,
  related_transaction_reference,employee_person_id,customer_reference,device_reference,event_type,tender_type,
  amount_minor,currency,processor_reference_token,item_reference,item_serial_masked,item_imei_masked,
  observed_at,source_system,details,payload_digest_sha256)
 values(p_event_key,p_location_id,p_register_reference,p_transaction_reference,p_related_transaction_reference,
  p_employee_person_id,p_customer_reference,p_device_reference,p_event_type,p_tender_type,p_amount_minor,
  p_currency,p_processor_reference_token,p_item_reference,p_item_serial_masked,p_item_imei_masked,
  p_observed_at,p_source_system,p_details,p_payload_digest_sha256)
 on conflict(event_key) do nothing returning id into v_id;
 if v_id is null then
  select id into v_id from public.mme_pos_fraud_events where event_key=p_event_key and location_id=p_location_id;
  if v_id is null then raise exception 'Fraud event key reused across locations' using errcode='23505'; end if;
 end if;
 return v_id;
end;
$$;

create or replace function public.mme_pos_create_fraud_assessment(
 p_event_id uuid,p_rule_id uuid,p_risk_score integer,p_explanation text,p_factors jsonb,p_ruleset_version text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_event public.mme_pos_fraud_events%rowtype; v_rule_version integer; v_id uuid; v_band text;
begin
 select * into v_event from public.mme_pos_fraud_events where id=p_event_id;
 if not found then raise exception 'Fraud event not found' using errcode='P0002'; end if;
 if p_risk_score not between 0 and 100 or jsonb_typeof(p_factors)<>'array'
  or length(btrim(coalesce(p_explanation,'')))<8 or length(btrim(coalesce(p_ruleset_version,'')))<1 then
  raise exception 'Invalid fraud assessment' using errcode='22023';
 end if;
 if p_rule_id is not null then
  select rule_version into v_rule_version from public.mme_pos_fraud_rules where id=p_rule_id and enabled=true;
  if v_rule_version is null then raise exception 'Fraud rule is not enabled' using errcode='55000'; end if;
 end if;
 v_band:=case when p_risk_score<20 then 'informational' when p_risk_score<40 then 'low'
  when p_risk_score<60 then 'moderate' when p_risk_score<80 then 'high' else 'critical' end;
 insert into public.mme_pos_fraud_assessments(event_id,location_id,rule_id,rule_version,risk_score,risk_band,
  explanation,contributing_factors,model_or_ruleset_version)
 values(p_event_id,v_event.location_id,p_rule_id,v_rule_version,p_risk_score,v_band,p_explanation,p_factors,p_ruleset_version)
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.mme_pos_create_fraud_case(
 p_case_key text,p_location_id uuid,p_title text,p_case_category text,p_priority text,p_summary text,
 p_actor_person_id uuid,p_event_id uuid
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
 if not public.mme_pos_authorize_fraud_action(p_actor_person_id,p_location_id,'pos.fraud.case.manage') then
  raise exception 'Fraud case creation permission denied' using errcode='42501';
 end if;
 if length(btrim(coalesce(p_summary,'')))<8 then raise exception 'Case summary required' using errcode='22023'; end if;
 insert into public.mme_pos_fraud_cases(case_key,location_id,title,case_category,priority,summary,opened_by_person_id)
 values(p_case_key,p_location_id,p_title,p_case_category,p_priority,p_summary,p_actor_person_id) returning id into v_id;
 if p_event_id is not null then
  if not exists(select 1 from public.mme_pos_fraud_events where id=p_event_id and location_id=p_location_id) then
   raise exception 'Fraud event does not belong to case location' using errcode='42501';
  end if;
  insert into public.mme_pos_fraud_case_events(case_id,event_id,linked_by_person_id) values(v_id,p_event_id,p_actor_person_id);
 end if;
 insert into public.mme_pos_fraud_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason)
 values(p_location_id,p_actor_person_id,'fraud_case_created','fraud_case',v_id::text,p_summary);
 return v_id;
end;
$$;

create or replace function public.mme_pos_review_fraud_case(
 p_case_id uuid,p_reviewer_person_id uuid,p_decision text,p_rationale text,p_evidence_reviewed jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_case public.mme_pos_fraud_cases%rowtype; v_id uuid;
begin
 select * into v_case from public.mme_pos_fraud_cases where id=p_case_id for update;
 if not found then raise exception 'Fraud case not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_fraud_action(p_reviewer_person_id,v_case.location_id,'pos.fraud.review') then
  raise exception 'Fraud review permission denied' using errcode='42501';
 end if;
 if length(btrim(coalesce(p_rationale,'')))<8 or jsonb_typeof(p_evidence_reviewed)<>'array' then
  raise exception 'Review rationale and evidence references required' using errcode='22023';
 end if;
 insert into public.mme_pos_fraud_reviews(case_id,reviewer_person_id,decision,rationale,evidence_reviewed)
 values(p_case_id,p_reviewer_person_id,p_decision,p_rationale,p_evidence_reviewed) returning id into v_id;
 update public.mme_pos_fraud_cases set status=case
  when p_decision='continue_review' then 'investigating'
  when p_decision='false_positive' then 'false_positive'
  when p_decision='inconclusive' then 'inconclusive'
  when p_decision='unsubstantiated' then 'closed'
  else 'review' end,updated_at=now() where id=p_case_id;
 insert into public.mme_pos_fraud_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason)
 values(v_case.location_id,p_reviewer_person_id,'fraud_case_reviewed','fraud_case',p_case_id::text,p_rationale);
 return v_id;
end;
$$;

create or replace function public.mme_pos_finalize_fraud_outcome(
 p_case_id uuid,p_approver_person_id uuid,p_outcome text,p_loss_amount_minor bigint,p_currency text,
 p_recovery_amount_minor bigint,p_notes text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_case public.mme_pos_fraud_cases%rowtype; v_id uuid;
begin
 select * into v_case from public.mme_pos_fraud_cases where id=p_case_id for update;
 if not found then raise exception 'Fraud case not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_fraud_action(p_approver_person_id,v_case.location_id,'pos.fraud.override') then
  raise exception 'Fraud outcome approval permission denied' using errcode='42501';
 end if;
 if p_loss_amount_minor<0 or p_recovery_amount_minor<0 then raise exception 'Invalid loss/recovery amount' using errcode='22023'; end if;
 insert into public.mme_pos_fraud_outcomes(case_id,outcome,loss_amount_minor,currency,recovery_amount_minor,
  approved_by_person_id,approved_at,notes)
 values(p_case_id,p_outcome,p_loss_amount_minor,p_currency,p_recovery_amount_minor,p_approver_person_id,now(),p_notes)
 returning id into v_id;
 update public.mme_pos_fraud_cases set status='resolved',resolved_at=now(),resolution_code=p_outcome,
  resolution_summary=coalesce(p_notes,p_outcome),updated_at=now() where id=p_case_id;
 insert into public.mme_pos_fraud_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason)
 values(v_case.location_id,p_approver_person_id,'fraud_outcome_finalized','fraud_case',p_case_id::text,coalesce(p_notes,p_outcome));
 return v_id;
end;
$$;

revoke all on function public.mme_pos_authorize_fraud_action(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_ingest_fraud_event(text,uuid,text,text,text,uuid,text,text,text,text,bigint,text,text,text,text,text,timestamptz,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_create_fraud_assessment(uuid,uuid,integer,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_create_fraud_case(text,uuid,text,text,text,text,uuid,uuid) from public,anon,authenticated;
revoke all on function public.mme_pos_review_fraud_case(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.mme_pos_finalize_fraud_outcome(uuid,uuid,text,bigint,text,bigint,text) from public,anon,authenticated;
grant execute on function public.mme_pos_authorize_fraud_action(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_ingest_fraud_event(text,uuid,text,text,text,uuid,text,text,text,text,bigint,text,text,text,text,text,timestamptz,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_create_fraud_assessment(uuid,uuid,integer,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_create_fraud_case(text,uuid,text,text,text,text,uuid,uuid) to service_role;
grant execute on function public.mme_pos_review_fraud_case(uuid,uuid,text,text,jsonb) to service_role;
grant execute on function public.mme_pos_finalize_fraud_outcome(uuid,uuid,text,bigint,text,bigint,text) to service_role;

comment on table public.mme_pos_fraud_events is 'POS anomaly telemetry. Never store PAN, full card number, CVV/CVC, PIN or track data; use processor references/tokens only.';
comment on table public.mme_pos_fraud_assessments is 'Explainable advisory risk assessment. A score is not proof of fraud or employee misconduct.';
comment on table public.mme_pos_fraud_cases is 'Human-reviewed fraud and transaction anomaly investigation records.';
commit;
