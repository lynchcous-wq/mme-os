begin;
create table public.mme_security_notification_provider_outages(
 outage_id uuid primary key default gen_random_uuid(),
 provider text not null references public.mme_security_notification_provider_health(provider) on delete restrict,
 channel text not null check(channel in ('email','sms','pager','push')),
 outage_key text not null,
 started_at timestamptz not null default now(),
 detected_at timestamptz not null default now(),
 recovered_at timestamptz,
 severity text not null default 'high' check(severity in ('medium','high','critical')),
 summary text not null check(length(summary)<=1000),
 last_observed_at timestamptz not null default now(),
 observation_count integer not null default 1,
 unique(provider,outage_key)
);
create index on public.mme_security_notification_provider_outages(started_at desc);
alter table public.mme_security_notification_provider_outages enable row level security;
revoke all on public.mme_security_notification_provider_outages from public,anon,authenticated;
grant select,insert,update on public.mme_security_notification_provider_outages to service_role;
create or replace function public.mme_security_notification_record_outage(p_provider text,p_channel text,p_outage_key text,p_severity text,p_summary text)
returns public.mme_security_notification_provider_outages
language plpgsql security definer set search_path=public,pg_temp as $$
declare o public.mme_security_notification_provider_outages%rowtype;
begin
 insert into public.mme_security_notification_provider_outages(provider,channel,outage_key,severity,summary)
 values(p_provider,p_channel,left(p_outage_key,160),p_severity,left(p_summary,1000))
 on conflict(provider,outage_key) do update set last_observed_at=now(),observation_count=mme_security_notification_provider_outages.observation_count+1,summary=excluded.summary
 returning * into o; return o;
end $$;
create or replace function public.mme_security_notification_recover_outage(p_provider text,p_channel text)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
 update public.mme_security_notification_provider_outages set recovered_at=now(),last_observed_at=now()
 where provider=p_provider and channel=p_channel and recovered_at is null;
 get diagnostics n=row_count; return n;
end $$;
create or replace view public.mme_security_notification_provider_performance
with(security_invoker=true) as
select h.provider,h.channel,h.enabled,h.circuit_state,h.priority,h.consecutive_failures,h.average_latency_ms,
 coalesce(c.checks_30d,0) as checks_30d,c.probe_success_pct_30d,c.p95_latency_ms_30d,
 coalesce(o.outages_30d,0) as outages_30d,o.last_outage_at
from public.mme_security_notification_provider_health h
left join lateral (
 select count(*) as checks_30d,
 round(100.0*count(*) filter(where healthy)/nullif(count(*),0),2) as probe_success_pct_30d,
 percentile_cont(0.95) within group(order by latency_ms) filter(where healthy) as p95_latency_ms_30d
 from public.mme_security_notification_provider_checks
 where provider=h.provider and checked_at>=now()-interval '30 days'
) c on true
left join lateral (
 select count(*) as outages_30d,max(started_at) as last_outage_at
 from public.mme_security_notification_provider_outages
 where provider=h.provider and started_at>=now()-interval '30 days'
) o on true;
revoke all on public.mme_security_notification_provider_performance from public,anon,authenticated;
grant select on public.mme_security_notification_provider_performance to service_role;
revoke all on function public.mme_security_notification_record_outage(text,text,text,text,text),public.mme_security_notification_recover_outage(text,text) from public,anon,authenticated;
grant execute on function public.mme_security_notification_record_outage(text,text,text,text,text),public.mme_security_notification_recover_outage(text,text) to service_role;
commit;