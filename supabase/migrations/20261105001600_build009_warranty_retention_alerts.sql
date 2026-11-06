-- Build 009.82: retention alert governance
begin;
create table public.mme_warranty_retention_alerts (
 alert_id uuid primary key default gen_random_uuid(),
 alert_key text not null unique,
 evidence_id uuid references public.mme_warranty_claim_evidence(evidence_id) on delete restrict,
 deletion_job_id uuid references public.mme_warranty_evidence_deletion_jobs(deletion_job_id) on delete restrict,
 alert_type text not null check(alert_type in ('upcoming_expiration','overdue_evidence','approval_pending','deletion_failed','legal_hold','exception_expiring','worker_stalled')),
 severity text not null check(severity in ('info','warning','high','critical')),
 status text not null default 'open' check(status in ('open','acknowledged','resolved','suppressed')),
 title text not null, detail_code text not null, due_at timestamptz,
 assigned_to uuid, acknowledged_by uuid, acknowledged_at timestamptz,
 resolved_by uuid, resolved_at timestamptz, resolution_code text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check((acknowledged_at is null and acknowledged_by is null) or (acknowledged_at is not null and acknowledged_by is not null)),
 check((resolved_at is null and resolved_by is null) or (resolved_at is not null and resolved_by is not null))
);
create index mme_warranty_retention_alerts_queue_idx on public.mme_warranty_retention_alerts(severity,created_at) where status='open';
create table public.mme_warranty_retention_alert_events (
 event_id bigint generated always as identity primary key,
 alert_id uuid not null references public.mme_warranty_retention_alerts(alert_id) on delete restrict,
 event_type text not null check(event_type in ('created','assigned','acknowledged','escalated','resolved','suppressed','delivery_attempted','delivery_failed')),
 actor_id uuid, channel text check(channel in ('in_app','email','sms','webhook','system')),
 outcome text not null check(outcome in ('recorded','sent','failed','skipped')),
 reason_code text not null, event_digest text not null, occurred_at timestamptz not null default now()
);
create index mme_warranty_retention_alert_events_timeline_idx on public.mme_warranty_retention_alert_events(alert_id,occurred_at);
create table public.mme_warranty_retention_notification_outbox (
 outbox_id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_warranty_retention_alerts(alert_id) on delete restrict,
 recipient_id uuid not null, channel text not null check(channel in ('in_app','email','sms','webhook')),
 template_code text not null, payload jsonb not null default '{}'::jsonb,
 status text not null default 'queued' check(status in ('queued','processing','sent','retry','failed','cancelled')),
 attempts integer not null default 0 check(attempts>=0), max_attempts integer not null default 5 check(max_attempts between 1 and 10),
 available_at timestamptz not null default now(), lease_token uuid, lease_expires_at timestamptz,
 provider_reference text, last_error_code text, idempotency_key text not null unique, created_at timestamptz not null default now(),
 check((status='processing')=(lease_token is not null and lease_expires_at is not null))
);
create index mme_warranty_retention_outbox_queue_idx on public.mme_warranty_retention_notification_outbox(available_at,created_at) where status in ('queued','retry');
create table public.mme_warranty_retention_escalation_rules (
 rule_id uuid primary key default gen_random_uuid(), alert_type text not null,
 severity text not null check(severity in ('info','warning','high','critical')),
 after_minutes integer not null check(after_minutes between 1 and 525600),
 target_role text not null check(target_role in ('warranty_specialist','manager','privacy_officer','ceo')),
 enabled boolean not null default true, rule_version text not null, created_by uuid not null, created_at timestamptz not null default now(),
 unique(alert_type,severity,after_minutes,target_role,rule_version)
);

-- Access controls and acknowledgement RPC
begin;
alter table public.mme_warranty_retention_alerts enable row level security;
alter table public.mme_warranty_retention_alert_events enable row level security;
alter table public.mme_warranty_retention_notification_outbox enable row level security;
alter table public.mme_warranty_retention_escalation_rules enable row level security;
revoke all on public.mme_warranty_retention_alerts,public.mme_warranty_retention_alert_events,public.mme_warranty_retention_notification_outbox,public.mme_warranty_retention_escalation_rules from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_retention_alerts to service_role;
grant select,insert on public.mme_warranty_retention_alert_events to service_role;
grant select,insert,update on public.mme_warranty_retention_notification_outbox,public.mme_warranty_retention_escalation_rules to service_role;
revoke update,delete,truncate on public.mme_warranty_retention_alert_events from public,anon,authenticated,service_role;
create or replace function public.mme_warranty_retention_acknowledge_alert(p_alert uuid,p_actor uuid) returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.mme_warranty_retention_alerts%rowtype;
begin
 select * into a from public.mme_warranty_retention_alerts where alert_id=p_alert for update;
 if a.alert_id is null or a.status not in ('open','acknowledged') then raise exception 'alert_not_actionable'; end if;
 update public.mme_warranty_retention_alerts set status='acknowledged',acknowledged_by=p_actor,acknowledged_at=coalesce(acknowledged_at,now()),updated_at=now() where alert_id=p_alert;
 insert into public.mme_warranty_retention_alert_events(alert_id,event_type,actor_id,outcome,reason_code,event_digest) values(p_alert,'acknowledged',p_actor,'recorded','staff_acknowledgement',encode(digest(p_alert::text||p_actor::text||clock_timestamp()::text,'sha256'),'hex'));
 return true;
end $$;
revoke all on function public.mme_warranty_retention_acknowledge_alert(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_warranty_retention_acknowledge_alert(uuid,uuid) to service_role;
commit;
