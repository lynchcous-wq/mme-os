begin;
create table public.mme_security_event_source_health(
 source_system text primary key check(source_system in ('pos','inventory','warranty','crm','evidence','payments','returns')),
 adapter_version text not null default '1.0.0',
 status text not null default 'unknown' check(status in ('unknown','healthy','degraded','offline','misconfigured')),
 last_event_at timestamptz,
 last_success_at timestamptz,
 last_failure_at timestamptz,
 consecutive_failures integer not null default 0 check(consecutive_failures>=0),
 accepted_count bigint not null default 0,
 rejected_count bigint not null default 0,
 last_error_code text,
 updated_at timestamptz not null default now()
);
create table public.mme_security_event_source_health_checks(
 check_id uuid primary key default gen_random_uuid(),
 source_system text not null references public.mme_security_event_source_health(source_system) on delete restrict,
 check_type text not null check(check_type in ('credential','delivery','heartbeat','schema')),
 outcome text not null check(outcome in ('success','failure','warning')),
 error_code text,
 latency_ms integer check(latency_ms is null or latency_ms>=0),
 checked_at timestamptz not null default now()
);
create index mme_security_source_health_checks_idx on public.mme_security_event_source_health_checks(source_system,checked_at desc);
alter table public.mme_security_event_source_health enable row level security;
alter table public.mme_security_event_source_health_checks enable row level security;
revoke all on public.mme_security_event_source_health from public,anon,authenticated;
revoke all on public.mme_security_event_source_health_checks from public,anon,authenticated;
grant select,insert,update on public.mme_security_event_source_health to service_role;
grant select,insert on public.mme_security_event_source_health_checks to service_role;
insert into public.mme_security_event_source_health(source_system) values ('pos'),('inventory'),('warranty'),('crm'),('evidence'),('payments'),('returns') on conflict do nothing;
commit;