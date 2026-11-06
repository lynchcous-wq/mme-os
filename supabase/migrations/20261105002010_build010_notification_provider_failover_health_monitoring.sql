begin;
create table public.mme_security_notification_provider_checks(
 check_id uuid primary key default gen_random_uuid(),
 provider text not null references public.mme_security_notification_provider_health(provider) on delete restrict,
 checked_at timestamptz not null default now(),
 healthy boolean not null,
 latency_ms integer check(latency_ms is null or latency_ms>=0),
 status_code integer,
 error_code text,
 details text check(details is null or length(details)<=500)
);
create index on public.mme_security_notification_provider_checks(provider,checked_at desc);
alter table public.mme_security_notification_provider_health
 add column if not exists failure_threshold integer not null default 3 check(failure_threshold between 1 and 20),
 add column if not exists recovery_threshold integer not null default 2 check(recovery_threshold between 1 and 20),
 add column if not exists last_check_at timestamptz,
 add column if not exists average_latency_ms integer,
 add column if not exists priority integer not null default 100;
alter table public.mme_security_notification_provider_checks enable row level security;
revoke all on public.mme_security_notification_provider_checks from public,anon,authenticated;
grant select,insert on public.mme_security_notification_provider_checks to service_role;
create or replace function public.mme_security_notification_record_health(
 p_provider text,p_channel text,p_healthy boolean,p_latency_ms integer default null,p_status_code integer default null,p_error_code text default null,p_details text default null
) returns public.mme_security_notification_provider_health
language plpgsql security definer set search_path=public,pg_temp as $$
declare h public.mme_security_notification_provider_health%rowtype; threshold integer; recover integer;
begin
 select * into h from public.mme_security_notification_provider_health where provider=p_provider and channel=p_channel for update;
 if not found then raise exception 'provider_not_registered'; end if;
 insert into public.mme_security_notification_provider_checks(provider,healthy,latency_ms,status_code,error_code,details)
 values(p_provider,p_healthy,p_latency_ms,p_status_code,left(p_error_code,80),left(p_details,500));
 threshold:=h.failure_threshold;recover:=h.recovery_threshold;
 if p_healthy then
  update public.mme_security_notification_provider_health set
   consecutive_failures=0,last_success_at=now(),last_check_at=now(),
   average_latency_ms=case when p_latency_ms is null then average_latency_ms else coalesce((average_latency_ms*4+p_latency_ms)/5,p_latency_ms) end,
   circuit_state=case when circuit_state='open' then 'half_open' when circuit_state='half_open' and (select count(*) from (select healthy from public.mme_security_notification_provider_checks where provider=p_provider order by checked_at desc limit recover) x where healthy)=recover then 'closed' else circuit_state end,
   updated_at=now() where provider=p_provider returning * into h;
 else
  update public.mme_security_notification_provider_health set consecutive_failures=consecutive_failures+1,last_failure_at=now(),last_check_at=now(),
   circuit_state=case when consecutive_failures+1>=threshold then 'open' else circuit_state end,updated_at=now()
   where provider=p_provider returning * into h;
 end if;
 return h;
end $$;
create or replace function public.mme_security_notification_select_provider(p_channel text,p_excluded text[] default '{}')
returns text language sql stable security definer set search_path=public,pg_temp as $$
 select provider from public.mme_security_notification_provider_health
 where channel=p_channel and enabled and circuit_state='closed' and not(provider=any(coalesce(p_excluded,'{}')))
 order by priority asc,coalesce(average_latency_ms,2147483647) asc,provider asc limit 1
$$;
revoke all on function public.mme_security_notification_record_health(text,text,boolean,integer,integer,text,text) from public,anon,authenticated;
revoke all on function public.mme_security_notification_select_provider(text,text[]) from public,anon,authenticated;
grant execute on function public.mme_security_notification_record_health(text,text,boolean,integer,integer,text,text),public.mme_security_notification_select_provider(text,text[]) to service_role;
commit;