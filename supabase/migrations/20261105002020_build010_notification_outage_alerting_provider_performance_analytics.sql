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
 count(c.check_id) filter(where c.checked_at>=now()-interval '30 days') as checks_30d,
 round(100.0*count(c.check_id) filter(where c.checked_at>=now()-interval '30 days' and c.healthy)/nullif(count(c.check_id) filter(where c.checked_at>=now()-interval '30 days'),0),2) as probe_success_pct_30d,
 percentile_cont(0.95) within group(order by c.latency_ms) filter(where c.checked_at>=now()-interval '30 days' and c.healthy) as p95_latency_ms_30d,
 count(o.outage_id) filter(where o.started_at>=now()-interval '30 days') as outages_30d,
 max(o.started_at) as last_outage_at
from public.mme_security_notification_provider_health h
left join public.mme_security_notification_provider_checks c on c.provider=h.provider
left join public.mme_security_notification_provider_outages o on o.provider=h.provider
group by h.provider,h.channel,h.enabled,h.circuit_state,h.priority,h.consecutive_failures,h.average_latency_ms;
revoke all on public.mme_security_notification_provider_performance from public,anon,authenticated;
grant select on public.mme_security_notification_provider_performance to service_role;
revoke all on function public.mme_security_notification_record_outage(text,text,text,text,text),public.mme_security_notification_recover_outage(text,text) from public,anon,authenticated;
grant execute on function public.mme_security_notification_record_outage(text,text,text,text,text),public.mme_security_notification_recover_outage(text,text) to service_role;
commit;