-- Build 009.27 — POS Hardware & Infrastructure Security Intelligence Center
-- Stores security telemetry, explainable alerts, investigation evidence and approved response intent.
-- This migration does not autonomously isolate devices or change network/firewall configuration.
begin;

create table public.mme_pos_security_rules (
 id uuid primary key default gen_random_uuid(),
 rule_key text not null unique check(length(btrim(rule_key)) between 3 and 120),
 rule_name text not null check(length(btrim(rule_name)) between 3 and 180),
 category text not null check(category in ('device_tampering','unauthorized_device','network_intrusion','certificate','firmware','payment_terminal','identity_access','configuration_drift','data_access','other')),
 severity text not null check(severity in ('low','medium','high','critical')),
 description text not null check(length(btrim(description)) between 8 and 2000),
 rule_definition jsonb not null check(jsonb_typeof(rule_definition)='object'),
 rule_version integer not null default 1 check(rule_version>0),
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

create table public.mme_pos_security_events (
 id uuid primary key default gen_random_uuid(),
 event_key text not null unique check(length(btrim(event_key)) between 8 and 200),
 location_id uuid not null,
 device_id uuid,
 category text not null check(category in ('device_tampering','unauthorized_device','network_intrusion','certificate','firmware','payment_terminal','identity_access','configuration_drift','data_access','other')),
 event_type text not null check(length(btrim(event_type)) between 3 and 120),
 severity text not null check(severity in ('info','low','medium','high','critical')),
 source_system text not null check(length(btrim(source_system)) between 2 and 100),
 observed_at timestamptz not null,
 received_at timestamptz not null default now(),
 actor_person_id uuid,
 external_event_reference text check(external_event_reference is null or length(external_event_reference)<=240),
 correlation_reference text check(correlation_reference is null or length(correlation_reference)<=240),
 details jsonb not null default '{}'::jsonb check(jsonb_typeof(details)='object'),
 payload_digest_sha256 text check(payload_digest_sha256 is null or payload_digest_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default now()
);
create index mme_pos_security_events_location_time_idx on public.mme_pos_security_events(location_id,observed_at desc);
create index mme_pos_security_events_device_time_idx on public.mme_pos_security_events(device_id,observed_at desc);
create index mme_pos_security_events_category_idx on public.mme_pos_security_events(category,severity,observed_at desc);

create table public.mme_pos_security_alerts (
 id uuid primary key default gen_random_uuid(),
 alert_key text not null unique check(length(btrim(alert_key)) between 8 and 200),
 location_id uuid not null,
 rule_id uuid references public.mme_pos_security_rules(id) on delete restrict,
 rule_version integer,
 primary_event_id uuid references public.mme_pos_security_events(id) on delete restrict,
 category text not null,
 severity text not null check(severity in ('info','low','medium','high','critical')),
 risk_score integer check(risk_score between 0 and 100),
 explanation text not null check(length(btrim(explanation)) between 8 and 2000),
 status text not null default 'open' check(status in ('open','triaged','investigating','contained','resolved','dismissed','false_positive')),
 assigned_to_person_id uuid,
 first_seen_at timestamptz not null,
 last_seen_at timestamptz not null,
 occurrence_count integer not null default 1 check(occurrence_count>0),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(last_seen_at>=first_seen_at)
);
create index mme_pos_security_alerts_queue_idx on public.mme_pos_security_alerts(location_id,status,severity,last_seen_at desc);

create table public.mme_pos_security_risk_scores (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 subject_type text not null check(subject_type in ('device','network_zone','register','payment_terminal','store','service')),
 subject_reference text not null check(length(btrim(subject_reference)) between 1 and 200),
 risk_score integer not null check(risk_score between 0 and 100),
 risk_band text not null check(risk_band in ('informational','low','moderate','high','critical')),
 factors jsonb not null check(jsonb_typeof(factors)='array'),
 scoring_version text not null check(length(btrim(scoring_version)) between 1 and 80),
 assessed_at timestamptz not null,
 expires_at timestamptz,
 created_at timestamptz not null default now(),
 check(expires_at is null or expires_at>assessed_at)
);
create index mme_pos_security_risk_subject_idx on public.mme_pos_security_risk_scores(location_id,subject_type,subject_reference,assessed_at desc);

create table public.mme_pos_security_incidents (
 id uuid primary key default gen_random_uuid(),
 incident_key text not null unique check(length(btrim(incident_key)) between 8 and 200),
 location_id uuid not null,
 title text not null check(length(btrim(title)) between 3 and 180),
 incident_type text not null check(length(btrim(incident_type)) between 3 and 120),
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'new' check(status in ('new','triage','investigating','containment_pending','contained','remediation','verification','resolved','closed','false_positive')),
 summary text not null check(length(btrim(summary)) between 8 and 3000),
 incident_commander_person_id uuid,
 opened_at timestamptz not null default now(),
 contained_at timestamptz,
 resolved_at timestamptz,
 closed_at timestamptz,
 closure_reason text check(closure_reason is null or length(closure_reason)<=2000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index mme_pos_security_incidents_queue_idx on public.mme_pos_security_incidents(location_id,status,severity,opened_at desc);

create table public.mme_pos_security_incident_alerts (
 incident_id uuid not null references public.mme_pos_security_incidents(id) on delete restrict,
 alert_id uuid not null references public.mme_pos_security_alerts(id) on delete restrict,
 linked_at timestamptz not null default now(),
 linked_by_person_id uuid,
 primary key(incident_id,alert_id)
);

create table public.mme_pos_security_evidence (
 id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_pos_security_incidents(id) on delete restrict,
 event_id uuid references public.mme_pos_security_events(id) on delete restrict,
 evidence_type text not null check(evidence_type in ('event_record','device_snapshot','network_snapshot','configuration_diff','firmware_attestation','certificate_metadata','processor_reference','log_export','image_reference','other')),
 evidence_reference text not null check(length(btrim(evidence_reference)) between 3 and 500),
 digest_sha256 text check(digest_sha256 is null or digest_sha256 ~ '^[a-f0-9]{64}$'),
 collected_by_person_id uuid,
 collected_at timestamptz not null,
 chain_of_custody jsonb not null default '[]'::jsonb check(jsonb_typeof(chain_of_custody)='array'),
 sensitivity text not null default 'internal' check(sensitivity in ('internal','confidential','restricted')),
 retention_until timestamptz,
 created_at timestamptz not null default now()
);
create index mme_pos_security_evidence_incident_idx on public.mme_pos_security_evidence(incident_id,collected_at);

create table public.mme_pos_security_actions (
 id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_pos_security_incidents(id) on delete restrict,
 action_type text not null check(action_type in ('request_device_isolation','disable_device_credential','revoke_certificate','block_network_peer','suspend_device_enrollment','preserve_logs','notify_it','notify_payment_provider','other')),
 target_reference text not null check(length(btrim(target_reference)) between 1 and 240),
 action_reason text not null check(length(btrim(action_reason)) between 8 and 1200),
 status text not null default 'pending_approval' check(status in ('pending_approval','approved','rejected','dispatched','succeeded','failed','cancelled')),
 requested_by_person_id uuid not null,
 approved_by_person_id uuid,
 executed_by_reference text,
 requested_at timestamptz not null default now(),
 approved_at timestamptz,
 executed_at timestamptz,
 result_summary text check(result_summary is null or length(result_summary)<=1200),
 check(approved_by_person_id is null or approved_by_person_id<>requested_by_person_id)
);
create index mme_pos_security_actions_queue_idx on public.mme_pos_security_actions(status,requested_at);

create table public.mme_pos_security_investigations (
 id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_pos_security_incidents(id) on delete restrict,
 investigator_person_id uuid not null,
 investigation_status text not null default 'assigned' check(investigation_status in ('assigned','active','awaiting_evidence','review','completed','cancelled')),
 scope text not null check(length(btrim(scope)) between 8 and 2000),
 findings_summary text check(findings_summary is null or length(findings_summary)<=3000),
 conclusion text check(conclusion is null or conclusion in ('confirmed_security_incident','unsubstantiated','false_positive','inconclusive','policy_gap')),
 started_at timestamptz,
 completed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(completed_at is null or started_at is not null and completed_at>=started_at)
);
create index mme_pos_security_investigations_assignee_idx on public.mme_pos_security_investigations(investigator_person_id,investigation_status);

create table public.mme_pos_security_audit_events (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null,
 actor_person_id uuid,
 action text not null check(length(btrim(action)) between 3 and 120),
 object_type text not null check(length(btrim(object_type)) between 3 and 120),
 object_reference text not null check(length(btrim(object_reference)) between 1 and 240),
 reason text not null check(length(btrim(reason)) between 8 and 1200),
 occurred_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object')
);
create index mme_pos_security_audit_location_idx on public.mme_pos_security_audit_events(location_id,occurred_at desc);

alter table public.mme_pos_security_rules enable row level security;
alter table public.mme_pos_security_events enable row level security;
alter table public.mme_pos_security_alerts enable row level security;
alter table public.mme_pos_security_risk_scores enable row level security;
alter table public.mme_pos_security_incidents enable row level security;
alter table public.mme_pos_security_incident_alerts enable row level security;
alter table public.mme_pos_security_evidence enable row level security;
alter table public.mme_pos_security_actions enable row level security;
alter table public.mme_pos_security_investigations enable row level security;
alter table public.mme_pos_security_audit_events enable row level security;

revoke all on public.mme_pos_security_rules,public.mme_pos_security_events,public.mme_pos_security_alerts,
 public.mme_pos_security_risk_scores,public.mme_pos_security_incidents,public.mme_pos_security_incident_alerts,
 public.mme_pos_security_evidence,public.mme_pos_security_actions,public.mme_pos_security_investigations,
 public.mme_pos_security_audit_events from public,anon,authenticated;
grant all on public.mme_pos_security_rules,public.mme_pos_security_events,public.mme_pos_security_alerts,
 public.mme_pos_security_risk_scores,public.mme_pos_security_incidents,public.mme_pos_security_incident_alerts,
 public.mme_pos_security_evidence,public.mme_pos_security_actions,public.mme_pos_security_investigations,
 public.mme_pos_security_audit_events to service_role;

create or replace function public.mme_pos_authorize_security_action(p_actor_person_id uuid,p_location_id uuid,p_permission text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
 if p_permission not in ('pos.security.view','pos.security.manage','pos.security.investigate','pos.security.contain','pos.security.rules.manage') then return false; end if;
 return public.mme_pos_authorize_hardware_action(p_actor_person_id,p_permission,p_location_id);
end;
$$;

create or replace function public.mme_pos_ingest_security_event(
 p_event_key text,p_location_id uuid,p_device_id uuid,p_category text,p_event_type text,p_severity text,
 p_source_system text,p_observed_at timestamptz,p_external_event_reference text,p_correlation_reference text,
 p_details jsonb,p_payload_digest_sha256 text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid;
begin
 if length(btrim(coalesce(p_event_key,'')))<8 or p_location_id is null or p_observed_at is null
  or p_details is null or jsonb_typeof(p_details)<>'object'
  or p_observed_at>now()+interval '5 minutes'
  or p_payload_digest_sha256 is not null and p_payload_digest_sha256 !~ '^[a-f0-9]{64}$' then
  raise exception 'Invalid security event payload' using errcode='22023';
 end if;
 insert into public.mme_pos_security_events(event_key,location_id,device_id,category,event_type,severity,source_system,
  observed_at,external_event_reference,correlation_reference,details,payload_digest_sha256)
 values(p_event_key,p_location_id,p_device_id,p_category,p_event_type,p_severity,p_source_system,p_observed_at,
  p_external_event_reference,p_correlation_reference,p_details,p_payload_digest_sha256)
 on conflict(event_key) do nothing returning id into v_id;
 if v_id is null then
  select id into v_id from public.mme_pos_security_events where event_key=p_event_key and location_id=p_location_id;
  if v_id is null then raise exception 'Event key reused across locations' using errcode='23505'; end if;
 end if;
 return v_id;
end;
$$;

create or replace function public.mme_pos_create_security_alert(
 p_alert_key text,p_location_id uuid,p_rule_id uuid,p_primary_event_id uuid,p_category text,p_severity text,
 p_risk_score integer,p_explanation text,p_first_seen_at timestamptz,p_last_seen_at timestamptz
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_id uuid; v_version integer;
begin
 if p_risk_score is not null and p_risk_score not between 0 and 100 then raise exception 'Risk score out of range' using errcode='22023'; end if;
 if p_last_seen_at<p_first_seen_at or length(btrim(coalesce(p_explanation,'')))<8 then raise exception 'Invalid alert evidence' using errcode='22023'; end if;
 if p_rule_id is not null then
  select rule_version into v_version from public.mme_pos_security_rules where id=p_rule_id and enabled=true;
  if v_version is null then raise exception 'Security rule is not enabled' using errcode='55000'; end if;
 end if;
 insert into public.mme_pos_security_alerts(alert_key,location_id,rule_id,rule_version,primary_event_id,category,severity,
  risk_score,explanation,first_seen_at,last_seen_at)
 values(p_alert_key,p_location_id,p_rule_id,v_version,p_primary_event_id,p_category,p_severity,p_risk_score,p_explanation,p_first_seen_at,p_last_seen_at)
 on conflict(alert_key) do nothing returning id into v_id;
 if v_id is null then
  update public.mme_pos_security_alerts set occurrence_count=occurrence_count+1,last_seen_at=greatest(last_seen_at,p_last_seen_at),
   updated_at=now() where alert_key=p_alert_key and location_id=p_location_id returning id into v_id;
  if v_id is null then raise exception 'Alert key reused across locations' using errcode='23505'; end if;
 end if;
 return v_id;
end;
$$;

create or replace function public.mme_pos_request_security_action(
 p_incident_id uuid,p_actor_person_id uuid,p_action_type text,p_target_reference text,p_reason text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v_incident public.mme_pos_security_incidents%rowtype; v_id uuid;
begin
 select * into v_incident from public.mme_pos_security_incidents where id=p_incident_id for update;
 if not found then raise exception 'Security incident not found' using errcode='P0002'; end if;
 if not public.mme_pos_authorize_security_action(p_actor_person_id,v_incident.location_id,'pos.security.contain') then
  raise exception 'Security containment permission denied' using errcode='42501';
 end if;
 if length(btrim(coalesce(p_reason,'')))<8 or length(btrim(coalesce(p_target_reference,'')))<1 then
  raise exception 'Action reason and target are required' using errcode='22023';
 end if;
 insert into public.mme_pos_security_actions(incident_id,action_type,target_reference,action_reason,requested_by_person_id)
 values(p_incident_id,p_action_type,p_target_reference,p_reason,p_actor_person_id) returning id into v_id;
 insert into public.mme_pos_security_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason)
 values(v_incident.location_id,p_actor_person_id,'security_action_requested','security_action',v_id::text,p_reason);
 return v_id;
end;
$$;

create or replace function public.mme_pos_approve_security_action(p_action_id uuid,p_actor_person_id uuid,p_decision text,p_reason text)
returns text language plpgsql security definer set search_path=pg_catalog,public
as $$
declare v public.mme_pos_security_actions%rowtype; v_incident public.mme_pos_security_incidents%rowtype;
begin
 select * into v from public.mme_pos_security_actions where id=p_action_id for update;
 if not found then raise exception 'Security action not found' using errcode='P0002'; end if;
 select * into v_incident from public.mme_pos_security_incidents where id=v.incident_id;
 if not public.mme_pos_authorize_security_action(p_actor_person_id,v_incident.location_id,'pos.security.contain')
  or p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<8 then
  raise exception 'Security action approval denied or reason missing' using errcode='42501';
 end if;
 if v.status<>'pending_approval' or v.requested_by_person_id=p_actor_person_id then
  raise exception 'Action already decided or requester attempted self-approval' using errcode='42501';
 end if;
 update public.mme_pos_security_actions set status=case when p_decision='approve' then 'approved' else 'rejected' end,
  approved_by_person_id=case when p_decision='approve' then p_actor_person_id else null end,
  approved_at=now(),result_summary=left(p_reason,1200) where id=p_action_id;
 insert into public.mme_pos_security_audit_events(location_id,actor_person_id,action,object_type,object_reference,reason)
 values(v_incident.location_id,p_actor_person_id,'security_action_'||p_decision,'security_action',p_action_id::text,p_reason);
 return p_decision;
end;
$$;

revoke all on function public.mme_pos_authorize_security_action(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.mme_pos_ingest_security_event(text,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.mme_pos_create_security_alert(text,uuid,uuid,uuid,text,text,integer,text,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function public.mme_pos_request_security_action(uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.mme_pos_approve_security_action(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.mme_pos_authorize_security_action(uuid,uuid,text) to service_role;
grant execute on function public.mme_pos_ingest_security_event(text,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text) to service_role;
grant execute on function public.mme_pos_create_security_alert(text,uuid,uuid,uuid,text,text,integer,text,timestamptz,timestamptz) to service_role;
grant execute on function public.mme_pos_request_security_action(uuid,uuid,text,text,text) to service_role;
grant execute on function public.mme_pos_approve_security_action(uuid,uuid,text,text) to service_role;

comment on table public.mme_pos_security_events is 'Normalized POS hardware and infrastructure security telemetry. Do not place credentials, payment card data or unnecessary personal data in event details.';
comment on table public.mme_pos_security_evidence is 'Evidence references and chain-of-custody metadata; store sensitive evidence in approved encrypted evidence storage.';
comment on table public.mme_pos_security_actions is 'Approved response intent only; a separately trusted adapter must execute supported containment actions and report verified results.';
commit;
