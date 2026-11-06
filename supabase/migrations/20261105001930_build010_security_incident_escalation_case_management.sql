begin;
create table public.mme_security_incidents(
 incident_id uuid primary key default gen_random_uuid(),
 incident_number bigint generated always as identity unique,
 alert_id uuid references public.mme_security_integration_alerts(alert_id) on delete restrict,
 source_system text not null check(source_system in ('pos','inventory','warranty','crm','evidence','payments','returns')),
 title text not null check(length(trim(title)) between 5 and 200),
 description text not null default '' check(length(description)<=10000),
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','triage','investigating','contained','pending_review','resolved','closed')),
 owner_user_id uuid,
 assigned_team text,
 created_by uuid not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 due_at timestamptz,
 contained_at timestamptz,
 resolved_at timestamptz,
 closed_at timestamptz,
 resolution_summary text,
 root_cause text,
 corrective_actions text,
 unique(alert_id)
);
create index mme_security_incidents_status_idx on public.mme_security_incidents(status,severity,created_at desc);
create index mme_security_incidents_owner_idx on public.mme_security_incidents(owner_user_id,status);
create table public.mme_security_incident_evidence(
 evidence_link_id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_security_incidents(incident_id) on delete restrict,
 evidence_ref text not null check(length(trim(evidence_ref)) between 1 and 500),
 evidence_type text not null check(evidence_type in ('file','event','case','url','log_reference')),
 description text not null default '' check(length(description)<=1000),
 added_by uuid not null,
 created_at timestamptz not null default now(),
 unique(incident_id,evidence_ref)
);
create table public.mme_security_incident_audit(
 audit_id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.mme_security_incidents(incident_id) on delete restrict,
 actor_user_id uuid not null,
 action text not null check(action in ('created','assigned','severity_changed','status_changed','evidence_linked','resolution_submitted','closed','note_added')),
 before_state jsonb,
 after_state jsonb,
 note text check(note is null or length(note)<=4000),
 created_at timestamptz not null default now()
);
create index mme_security_incident_audit_incident_idx on public.mme_security_incident_audit(incident_id,created_at desc);
create table public.mme_security_incident_escalation_policies(
 severity text primary key check(severity in ('low','medium','high','critical')),
 response_minutes integer not null check(response_minutes between 1 and 10080),
 escalate_to text not null,
 enabled boolean not null default true,
 updated_at timestamptz not null default now()
);
insert into public.mme_security_incident_escalation_policies(severity,response_minutes,escalate_to) values
('low',1440,'it_admin'),('medium',240,'it_admin'),('high',60,'cio'),('critical',15,'ceo;cio') on conflict(severity) do nothing;
alter table public.mme_security_incidents enable row level security;
alter table public.mme_security_incident_evidence enable row level security;
alter table public.mme_security_incident_audit enable row level security;
alter table public.mme_security_incident_escalation_policies enable row level security;
revoke all on public.mme_security_incidents,public.mme_security_incident_evidence,public.mme_security_incident_audit,public.mme_security_incident_escalation_policies from public,anon,authenticated;
grant select,insert,update on public.mme_security_incidents to service_role;
grant select,insert on public.mme_security_incident_evidence,public.mme_security_incident_audit to service_role;
grant select,insert,update on public.mme_security_incident_escalation_policies to service_role;
create or replace function public.mme_security_incident_create_from_alert(p_alert uuid,p_actor uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.mme_security_integration_alerts%rowtype; i uuid; mins integer;
begin
 select * into a from public.mme_security_integration_alerts where alert_id=p_alert for update;
 if not found then raise exception 'alert_not_found'; end if;
 insert into public.mme_security_incidents(alert_id,source_system,title,description,severity,created_by,due_at)
 values(a.alert_id,a.source_system,'Security alert: '||a.policy_key,a.message,
 case a.severity when 'critical' then 'critical' when 'warning' then 'high' else 'medium' end,p_actor,
 now()+make_interval(mins=>(select response_minutes from public.mme_security_incident_escalation_policies where severity=case a.severity when 'critical' then 'critical' when 'warning' then 'high' else 'medium' end)))
 on conflict(alert_id) do update set alert_id=excluded.alert_id returning incident_id into i;
 insert into public.mme_security_incident_audit(incident_id,actor_user_id,action,after_state)
 values(i,p_actor,'created',jsonb_build_object('alert_id',a.alert_id,'source_system',a.source_system,'severity',a.severity))
 on conflict do nothing;
 return i;
end $$;
revoke all on function public.mme_security_incident_create_from_alert(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_security_incident_create_from_alert(uuid,uuid) to service_role;
commit;