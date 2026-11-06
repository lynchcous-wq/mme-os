begin;
create table public.mme_security_notification_escalation_policies(
 policy_id uuid primary key default gen_random_uuid(),
 policy_key text not null unique,
 severity text not null check(severity in ('medium','high','critical')),
 enabled boolean not null default true,
 acknowledge_within_minutes integer not null check(acknowledge_within_minutes between 1 and 1440),
 escalation_roles text[] not null default array['cio','ceo']::text[],
 max_escalation_level integer not null default 3 check(max_escalation_level between 1 and 5),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.mme_security_notification_escalation_alerts(
 alert_id uuid primary key default gen_random_uuid(),
 source_key text not null unique,
 title text not null check(length(title) between 1 and 200),
 summary text not null check(length(summary)<=2000),
 severity text not null check(severity in ('medium','high','critical')),
 department text,
 target_roles text[] not null default array['cio']::text[],
 escalation_level integer not null default 1 check(escalation_level between 1 and 5),
 status text not null default 'open' check(status in ('open','acknowledged','resolved','expired')),
 created_at timestamptz not null default now(),
 acknowledge_by timestamptz not null,
 acknowledged_at timestamptz,
 acknowledged_by uuid,
 resolved_at timestamptz,
 last_escalated_at timestamptz,
 escalation_count integer not null default 0
);
create table public.mme_security_notification_escalation_events(
 event_id uuid primary key default gen_random_uuid(),
 alert_id uuid not null references public.mme_security_notification_escalation_alerts(alert_id) on delete restrict,
 event_type text not null check(event_type in ('created','escalated','acknowledged','resolved','deadline_missed')),
 from_level integer,
 to_level integer,
 actor_id uuid,
 event_at timestamptz not null default now(),
 details text check(details is null or length(details)<=1000)
);
create index on public.mme_security_notification_escalation_alerts(status,acknowledge_by,severity);
create index on public.mme_security_notification_escalation_events(alert_id,event_at desc);
alter table public.mme_security_notification_escalation_policies enable row level security;
alter table public.mme_security_notification_escalation_alerts enable row level security;
alter table public.mme_security_notification_escalation_events enable row level security;
revoke all on public.mme_security_notification_escalation_policies,public.mme_security_notification_escalation_alerts,public.mme_security_notification_escalation_events from public,anon,authenticated;
grant select,insert,update on public.mme_security_notification_escalation_policies,public.mme_security_notification_escalation_alerts,public.mme_security_notification_escalation_events to service_role;
create or replace function public.mme_security_notification_create_escalation_alert(p_source_key text,p_title text,p_summary text,p_severity text,p_department text default null)
returns public.mme_security_notification_escalation_alerts
language plpgsql security definer set search_path=public,pg_temp as $$
declare pol public.mme_security_notification_escalation_policies%rowtype; a public.mme_security_notification_escalation_alerts%rowtype;
begin
 select * into pol from public.mme_security_notification_escalation_policies where severity=p_severity and enabled order by created_at desc limit 1;
 if not found then raise exception 'escalation_policy_not_configured'; end if;
 insert into public.mme_security_notification_escalation_alerts(source_key,title,summary,severity,department,target_roles,acknowledge_by)
 values(left(p_source_key,200),left(p_title,200),left(p_summary,2000),p_severity,left(p_department,100),pol.escalation_roles,now()+make_interval(mins=>pol.acknowledge_within_minutes))
 on conflict(source_key) do update set summary=excluded.summary
 returning * into a;
 if a.escalation_count=0 then insert into public.mme_security_notification_escalation_events(alert_id,event_type,to_level,details) values(a.alert_id,'created',1,'Escalation alert created'); end if;
 return a;
end $$;
create or replace function public.mme_security_notification_escalate_due(p_limit integer default 50)
returns setof public.mme_security_notification_escalation_alerts
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 return query
 with due as (
  select a.alert_id,p.max_escalation_level,p.escalation_roles
  from public.mme_security_notification_escalation_alerts a
  join lateral (select max(max_escalation_level) max_escalation_level,array_agg(distinct unnest_role) escalation_roles
   from public.mme_security_notification_escalation_policies p
   cross join lateral unnest(p.escalation_roles) unnest_role
   where p.enabled and p.severity=a.severity) p on true
  where a.status='open' and a.acknowledge_by<=now() and a.escalation_level<p.max_escalation_level
  order by a.acknowledge_by for update of a skip locked limit greatest(1,least(p_limit,100))
 ), upd as (
  update public.mme_security_notification_escalation_alerts a
  set escalation_level=a.escalation_level+1,target_roles=case when a.escalation_level+1>=2 then array['cio','ceo']::text[] else due.escalation_roles end,
      acknowledge_by=now()+interval '15 minutes',last_escalated_at=now(),escalation_count=a.escalation_count+1
  from due where a.alert_id=due.alert_id returning a.*
 ), logged as (
  insert into public.mme_security_notification_escalation_events(alert_id,event_type,from_level,to_level,details)
  select upd.alert_id,'escalated',upd.escalation_level-1,upd.escalation_level,'Acknowledgement deadline missed; alert escalated'
  from upd returning alert_id
 )
 select upd.* from upd join logged using(alert_id);
end $$;
create or replace function public.mme_security_notification_acknowledge_escalation(p_alert uuid,p_actor uuid)
returns public.mme_security_notification_escalation_alerts
language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.mme_security_notification_escalation_alerts%rowtype;
begin
 update public.mme_security_notification_escalation_alerts set status='acknowledged',acknowledged_at=now(),acknowledged_by=p_actor
 where alert_id=p_alert and status='open' returning * into a;
 if not found then raise exception 'alert_not_open_or_not_found'; end if;
 insert into public.mme_security_notification_escalation_events(alert_id,event_type,from_level,to_level,actor_id,details)
 values(a.alert_id,'acknowledged',a.escalation_level,a.escalation_level,p_actor,'Alert acknowledged by authorized operator');
 return a;
end $$;
revoke all on function public.mme_security_notification_create_escalation_alert(text,text,text,text,text),public.mme_security_notification_escalate_due(integer),public.mme_security_notification_acknowledge_escalation(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mme_security_notification_create_escalation_alert(text,text,text,text,text),public.mme_security_notification_escalate_due(integer),public.mme_security_notification_acknowledge_escalation(uuid,uuid) to service_role;
commit;