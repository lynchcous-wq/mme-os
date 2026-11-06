-- Build 009.86: compliance API security monitoring and incident management
begin;
create table public.mme_warranty_api_security_events (
 event_id bigint generated always as identity primary key,
 event_key text not null unique,
 request_id uuid,
 actor_id uuid,
 event_type text not null check(event_type in ('authentication_failure','authorization_denial','rate_limit_exceeded','api_error','access_anomaly','suspicious_ip')),
 severity text not null check(severity in ('info','warning','high','critical')),
 source_resource text not null check(source_resource in ('summary','calendar','approvals','alerts','assignments','unknown')),
 actor_role text,
 ip_digest text,
 reason_code text not null,
 occurrence_count integer not null default 1 check(occurrence_count>0),
 first_seen_at timestamptz not null default now(),
 last_seen_at timestamptz not null default now(),
 status text not null default 'open' check(status in ('open','investigating','resolved','false_positive')),
 created_at timestamptz not null default now()
);
create index mme_warranty_api_security_events_queue_idx on public.mme_warranty_api_security_events(severity,last_seen_at desc) where status in ('open','investigating');
create table public.mme_warranty_api_security_incidents (
 incident_id uuid primary key default gen_random_uuid(),
 incident_number bigint generated always as identity unique,
 title text not null,
 description text not null,
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'open' check(status in ('open','investigating','contained','resolved','closed')),
 owner_id uuid,
 resolution_code text,
 opened_at timestamptz not null default now(),
 contained_at timestamptz,
 resolved_at timestamptz,
 closed_at timestamptz,
 updated_at timestamptz not null default now(),
 check((resolved_at is null) or status in ('resolved','closed'))
);
create table public.mme_warranty_api_security_incident_events (
 event_id bigint generated always as identity primary key,
 incident_id uuid not null references public.mme_warranty_api_security_incidents(incident_id) on delete restrict,
 security_event_id bigint references public.mme_warranty_api_security_events(event_id) on delete restrict,
 actor_id uuid,
 event_type text not null check(event_type in ('created','assigned','investigation_note','contained','resolved','closed','reopened')),
 note text,
 reason_code text not null,
 occurred_at timestamptz not null default now()
);
create table public.mme_warranty_api_security_monitoring_rules (
 rule_id uuid primary key default gen_random_uuid(),
 event_type text not null,
 threshold_count integer not null check(threshold_count between 1 and 10000),
 window_minutes integer not null check(window_minutes between 1 and 1440),
 severity text not null check(severity in ('info','warning','high','critical')),
 enabled boolean not null default true,
 created_by uuid not null,
 created_at timestamptz not null default now(),
 unique(event_type,threshold_count,window_minutes)
);
alter table public.mme_warranty_api_security_events enable row level security;
alter table public.mme_warranty_api_security_incidents enable row level security;
alter table public.mme_warranty_api_security_incident_events enable row level security;
alter table public.mme_warranty_api_security_monitoring_rules enable row level security;
revoke all on public.mme_warranty_api_security_events,public.mme_warranty_api_security_incidents,public.mme_warranty_api_security_incident_events,public.mme_warranty_api_security_monitoring_rules from public,anon,authenticated;
grant select,insert,update on public.mme_warranty_api_security_events to service_role;
grant select,insert,update on public.mme_warranty_api_security_incidents to service_role;
grant select,insert on public.mme_warranty_api_security_incident_events to service_role;
grant select,insert,update on public.mme_warranty_api_security_monitoring_rules to service_role;
revoke update,delete,truncate on public.mme_warranty_api_security_incident_events from public,anon,authenticated,service_role;

create or replace function public.mme_warranty_api_record_security_event(
 p_event_key text,p_request_id uuid,p_actor_id uuid,p_event_type text,p_severity text,
 p_resource text,p_actor_role text,p_ip_digest text,p_reason_code text
) returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id bigint;
begin
 if p_event_type not in ('authentication_failure','authorization_denial','rate_limit_exceeded','api_error','access_anomaly','suspicious_ip') then raise exception 'invalid_security_event_type'; end if;
 if p_severity not in ('info','warning','high','critical') then raise exception 'invalid_security_event_severity'; end if;
 if p_resource not in ('summary','calendar','approvals','alerts','assignments','unknown') then raise exception 'invalid_security_event_resource'; end if;
 insert into public.mme_warranty_api_security_events(event_key,request_id,actor_id,event_type,severity,source_resource,actor_role,ip_digest,reason_code)
 values(left(p_event_key,180),p_request_id,p_actor_id,p_event_type,p_severity,p_resource,p_actor_role,p_ip_digest,left(p_reason_code,80))
 on conflict(event_key) do update set occurrence_count=public.mme_warranty_api_security_events.occurrence_count+1,last_seen_at=now()
 returning event_id into v_id;
 return v_id;
end $$;
revoke all on function public.mme_warranty_api_record_security_event(text,uuid,uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.mme_warranty_api_record_security_event(text,uuid,uuid,text,text,text,text,text,text) to service_role;

create or replace view public.mme_warranty_api_security_monitoring_dashboard with (security_invoker=true) as
select severity,status,event_type,source_resource,count(*) as event_groups,
 sum(occurrence_count) as total_occurrences,max(last_seen_at) as latest_seen_at
from public.mme_warranty_api_security_events
where status in ('open','investigating')
group by severity,status,event_type,source_resource;
create or replace view public.mme_warranty_api_security_incident_queue with (security_invoker=true) as
select incident_id,incident_number,title,description,severity,status,owner_id,opened_at,contained_at,resolved_at,updated_at
from public.mme_warranty_api_security_incidents where status not in ('closed','resolved');
revoke all on public.mme_warranty_api_security_monitoring_dashboard,public.mme_warranty_api_security_incident_queue from public,anon,authenticated;
grant select on public.mme_warranty_api_security_monitoring_dashboard,public.mme_warranty_api_security_incident_queue to service_role;
commit;
