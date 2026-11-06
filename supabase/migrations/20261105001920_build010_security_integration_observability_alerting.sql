begin;
create table public.mme_security_integration_metrics(
 metric_id uuid primary key default gen_random_uuid(),
 source_system text not null check(source_system in ('pos','inventory','warranty','crm','evidence','payments','returns')),
 metric_name text not null check(metric_name in ('delivery_success','delivery_failure','delivery_latency_ms','queue_backlog','dead_letter_count','circuit_open')),
 metric_value numeric not null check(metric_value>=0),
 request_id text,
 provider text check(provider is null or provider in ('primary','secondary')),
 observed_at timestamptz not null default now()
);
create index mme_security_integration_metrics_source_time_idx on public.mme_security_integration_metrics(source_system,observed_at desc);
create table public.mme_security_integration_alert_policies(
 policy_id uuid primary key default gen_random_uuid(),
 policy_key text not null unique,
 metric_name text not null check(metric_name in ('delivery_failure','delivery_latency_ms','queue_backlog','dead_letter_count','circuit_open')),
 threshold numeric not null check(threshold>=0),
 window_minutes integer not null default 5 check(window_minutes between 1 and 1440),
 severity text not null default 'warning' check(severity in ('info','warning','critical')),
 enabled boolean not null default true,
 updated_at timestamptz not null default now()
);
create table public.mme_security_integration_alerts(
 alert_id uuid primary key default gen_random_uuid(),
 policy_key text not null,
 source_system text not null check(source_system in ('pos','inventory','warranty','crm','evidence','payments','returns')),
 severity text not null check(severity in ('info','warning','critical')),
 status text not null default 'open' check(status in ('open','acknowledged','resolved')),
 metric_name text not null,
 metric_value numeric not null,
 threshold numeric not null,
 message text not null,
 opened_at timestamptz not null default now(),
 acknowledged_at timestamptz,
 acknowledged_by uuid,
 resolved_at timestamptz
);
create index mme_security_integration_alerts_status_idx on public.mme_security_integration_alerts(status,opened_at desc);
alter table public.mme_security_integration_metrics enable row level security;
alter table public.mme_security_integration_alert_policies enable row level security;
alter table public.mme_security_integration_alerts enable row level security;
revoke all on public.mme_security_integration_metrics from public,anon,authenticated;
revoke all on public.mme_security_integration_alert_policies from public,anon,authenticated;
revoke all on public.mme_security_integration_alerts from public,anon,authenticated;
grant select,insert on public.mme_security_integration_metrics to service_role;
grant select,insert,update on public.mme_security_integration_alert_policies to service_role;
grant select,insert,update on public.mme_security_integration_alerts to service_role;
insert into public.mme_security_integration_alert_policies(policy_key,metric_name,threshold,window_minutes,severity) values
('delivery-failure-warning','delivery_failure',3,5,'warning'),
('delivery-latency-critical','delivery_latency_ms',5000,5,'critical'),
('queue-backlog-warning','queue_backlog',50,5,'warning'),
('dead-letter-critical','dead_letter_count',1,5,'critical'),
('circuit-open-critical','circuit_open',1,5,'critical') on conflict(policy_key) do nothing;
create or replace function public.mme_security_integration_evaluate_alerts(p_source text)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare p record; v numeric; n integer:=0;
begin
 for p in select * from public.mme_security_integration_alert_policies where enabled loop
  select case
   when p.metric_name='delivery_failure' then count(*)::numeric
   when p.metric_name='delivery_latency_ms' then coalesce(avg(metric_value),0)
   when p.metric_name in ('queue_backlog','dead_letter_count','circuit_open') then coalesce(max(metric_value),0)
  end into v from public.mme_security_integration_metrics
  where source_system=p_source and metric_name=p.metric_name and observed_at>=now()-make_interval(mins=>p.window_minutes);
  if v>=p.threshold then
   insert into public.mme_security_integration_alerts(policy_key,source_system,severity,metric_name,metric_value,threshold,message)
   select p.policy_key,p_source,p.severity,p.metric_name,v,p.threshold,p.policy_key||' threshold breached for '||p_source
   where not exists(select 1 from public.mme_security_integration_alerts a where a.policy_key=p.policy_key and a.source_system=p_source and a.status='open' and a.opened_at>now()-make_interval(mins=>p.window_minutes));
   if found then n:=n+1; end if;
  end if;
 end loop;
 return n;
end $$;
revoke all on function public.mme_security_integration_evaluate_alerts(text) from public,anon,authenticated;
grant execute on function public.mme_security_integration_evaluate_alerts(text) to service_role;
commit;